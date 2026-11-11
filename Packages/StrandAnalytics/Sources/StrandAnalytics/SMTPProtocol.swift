import Foundation

// SMTPProtocol.swift — the wire side of sending one email, with no networking in it.
//
// Split this way so the whole conversation can be tested without a socket: `SMTPMessage` renders the
// bytes of a message, `SMTPReplyParser` turns received bytes into server replies, and `SMTPSession`
// decides what to say next. The app's transport only moves bytes between a TLS connection and these.
//
// Scope is deliberately one authenticated submission over an already-encrypted connection (implicit
// TLS, port 465): no STARTTLS, no pipelining, one recipient. That is all a daily summary needs.

public enum SMTPError: Error, Equatable, Sendable {
    /// A header or address contained a line break or control character. Rejected outright rather than
    /// stripped, because a value that carries one is either corrupt or an injection attempt.
    case invalidField(String)
    /// The server answered with a code the conversation cannot continue from. The text is the
    /// server's own, with the credentials never part of it.
    case rejected(stage: String, code: Int, text: String)
    case malformedReply(String)
}

public struct SMTPMessage: Equatable, Sendable {
    public let from: String
    public let to: String
    public let subject: String
    public let body: String
    public let date: Date
    public let messageId: String

    public init(from: String, to: String, subject: String, body: String, date: Date, messageId: String) {
        self.from = from; self.to = to; self.subject = subject; self.body = body
        self.date = date; self.messageId = messageId
    }

    /// The bare address inside `Name <addr@host>`, or the string itself when there are no brackets.
    public static func address(in mailbox: String) -> String {
        guard let open = mailbox.lastIndex(of: "<"), let close = mailbox.lastIndex(of: ">"), open < close else {
            return mailbox.trimmingCharacters(in: .whitespaces)
        }
        return String(mailbox[mailbox.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
    }

    /// Throws unless `value` is free of control characters and, for an address, shaped like one.
    static func validate(_ value: String, field: String, isAddress: Bool) throws {
        guard !value.isEmpty,
              !value.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) else {
            throw SMTPError.invalidField(field)
        }
        guard isAddress else { return }
        let addr = address(in: value)
        let parts = addr.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."),
              !addr.contains(" "), !addr.contains("<"), !addr.contains(">") else {
            throw SMTPError.invalidField(field)
        }
    }

    /// The complete message as it goes after `DATA`, CRLF line endings, WITHOUT the terminating
    /// `<CRLF>.<CRLF>`. The body is base64-encoded, which also means no line can begin with a dot and
    /// no line can exceed the 998-octet limit, whatever the text contains.
    public func rendered() throws -> String {
        try Self.validate(from, field: "from", isAddress: true)
        try Self.validate(to, field: "to", isAddress: true)
        try Self.validate(subject, field: "subject", isAddress: false)
        try Self.validate(messageId, field: "messageId", isAddress: false)

        let headers = [
            "From: \(from)",
            "To: \(to)",
            "Subject: \(Self.encodedHeader(subject))",
            "Date: \(Self.rfc2822(date))",
            "Message-ID: <\(messageId)>",
            "MIME-Version: 1.0",
            "Content-Type: text/plain; charset=utf-8",
            "Content-Transfer-Encoding: base64",
        ]
        let encoded = Data(body.utf8).base64EncodedString()
        return (headers + [""] + Self.chunk(encoded, every: 76)).joined(separator: "\r\n") + "\r\n"
    }

    /// RFC 2047 encoded-words when the text is not plain ASCII; unchanged otherwise. Split so no
    /// encoded-word exceeds the 75-character limit.
    static func encodedHeader(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: { $0.value > 0x7E }) else { return text }
        var words: [String] = []
        var current = ""
        for character in text {
            if Data((current + String(character)).utf8).count > 39 {   // 39 bytes -> 52 base64 chars
                words.append(current); current = ""
            }
            current.append(character)
        }
        if !current.isEmpty { words.append(current) }
        return words.map { "=?utf-8?B?\(Data($0.utf8).base64EncodedString())?=" }.joined(separator: "\r\n ")
    }

    static func chunk(_ text: String, every size: Int) -> [String] {
        var lines: [String] = []
        var index = text.startIndex
        while index < text.endIndex {
            let end = text.index(index, offsetBy: size, limitedBy: text.endIndex) ?? text.endIndex
            lines.append(String(text[index..<end]))
            index = end
        }
        return lines
    }

    static func rfc2822(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss '+0000'"
        return formatter.string(from: date)
    }
}

/// One complete server reply: its three-digit code and the text of every line.
public struct SMTPReply: Equatable, Sendable {
    public let code: Int
    public let lines: [String]
    public var text: String { lines.joined(separator: " ") }
    public init(code: Int, lines: [String]) { self.code = code; self.lines = lines }
}

/// Accumulates received bytes and yields replies as they complete. A reply spans several lines when
/// every line but the last has a hyphen after the code (`250-...` then `250 ...`).
public struct SMTPReplyParser: Sendable {
    private var buffer = ""
    private var pending: [String] = []

    public init() {}

    public mutating func append(_ text: String) throws -> [SMTPReply] {
        buffer += text
        var replies: [SMTPReply] = []
        while let range = buffer.range(of: "\r\n") {
            let line = String(buffer[buffer.startIndex..<range.lowerBound])
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)
            guard line.count >= 3, let code = Int(line.prefix(3)) else {
                throw SMTPError.malformedReply(String(line.prefix(80)))
            }
            let rest = line.dropFirst(3)
            pending.append(String(rest.dropFirst()))
            if rest.first != "-" {
                replies.append(SMTPReply(code: code, lines: pending))
                pending = []
            }
        }
        return replies
    }
}

/// The client's side of the conversation. Feed it each server reply; it answers with what to send.
public struct SMTPSession: Sendable {
    public enum Action: Equatable, Sendable {
        case send(String)
        /// The message was accepted. The connection can be closed.
        case finished
    }

    enum Stage: String, Sendable { case greeting, ehlo, auth, mailFrom, rcptTo, data, body, quit, done }

    private var stage: Stage = .greeting
    private let username: String
    private let password: String
    private let envelopeFrom: String
    private let envelopeTo: String
    private let payload: String

    public init(username: String, password: String, message: SMTPMessage) throws {
        try SMTPMessage.validate(username, field: "username", isAddress: false)
        try SMTPMessage.validate(password, field: "password", isAddress: false)
        self.username = username
        self.password = password
        self.envelopeFrom = SMTPMessage.address(in: message.from)
        self.envelopeTo = SMTPMessage.address(in: message.to)
        self.payload = try message.rendered()
    }

    public mutating func next(after reply: SMTPReply) throws -> Action {
        func expect(_ codes: Int...) throws {
            guard codes.contains(reply.code) else {
                throw SMTPError.rejected(stage: stage.rawValue, code: reply.code, text: reply.text)
            }
        }
        switch stage {
        case .greeting:
            try expect(220)
            stage = .ehlo
            return .send("EHLO localhost\r\n")
        case .ehlo:
            try expect(250)
            stage = .auth
            let token = Data("\u{0}\(username)\u{0}\(password)".utf8).base64EncodedString()
            return .send("AUTH PLAIN \(token)\r\n")
        case .auth:
            try expect(235)
            stage = .mailFrom
            return .send("MAIL FROM:<\(envelopeFrom)>\r\n")
        case .mailFrom:
            try expect(250)
            stage = .rcptTo
            return .send("RCPT TO:<\(envelopeTo)>\r\n")
        case .rcptTo:
            try expect(250, 251)
            stage = .data
            return .send("DATA\r\n")
        case .data:
            try expect(354)
            stage = .body
            return .send(payload + ".\r\n")
        case .body:
            try expect(250)
            stage = .quit
            return .send("QUIT\r\n")
        case .quit, .done:
            stage = .done
            return .finished
        }
    }

    /// True once the server has accepted the message, even if `QUIT` was never acknowledged — the
    /// point after which a retry would send a duplicate.
    public var messageAccepted: Bool { stage == .quit || stage == .done }
}
