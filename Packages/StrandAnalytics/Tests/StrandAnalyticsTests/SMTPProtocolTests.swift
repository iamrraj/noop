import XCTest
@testable import StrandAnalytics

final class SMTPProtocolTests: XCTestCase {

    private func message(from: String = "NOOP <noop@mg.example.com>", to: String = "rahul@example.com",
                         subject: String = "Mum: daily summary", body: String = "Hello") -> SMTPMessage {
        SMTPMessage(from: from, to: to, subject: subject, body: body,
                    date: Date(timeIntervalSince1970: 1_794_355_200), messageId: "abc123@noop")
    }

    private func reply(_ code: Int, _ text: String = "ok") -> SMTPReply { SMTPReply(code: code, lines: [text]) }

    // MARK: - Message rendering

    func testRenderedHeadersAndBase64Body() throws {
        let text = try message().rendered()
        let parts = text.components(separatedBy: "\r\n\r\n")
        XCTAssertEqual(parts.count, 2)
        let headers = parts[0].components(separatedBy: "\r\n")
        XCTAssertEqual(headers[0], "From: NOOP <noop@mg.example.com>")
        XCTAssertEqual(headers[1], "To: rahul@example.com")
        XCTAssertEqual(headers[2], "Subject: Mum: daily summary")
        XCTAssertTrue(headers[3].hasPrefix("Date: ") && headers[3].hasSuffix("+0000"))
        XCTAssertEqual(headers[4], "Message-ID: <abc123@noop>")
        XCTAssertTrue(headers.contains("Content-Transfer-Encoding: base64"))
        XCTAssertEqual(parts[1], Data("Hello".utf8).base64EncodedString() + "\r\n")
    }

    func testLongBodyIsWrappedAndRoundTrips() throws {
        let body = String(repeating: "Steps: 4200 — ünïcode line\n.\n", count: 40)
        let text = try message(body: body).rendered()
        let encodedLines = text.components(separatedBy: "\r\n\r\n")[1]
            .components(separatedBy: "\r\n").filter { !$0.isEmpty }
        XCTAssertTrue(encodedLines.allSatisfy { $0.count <= 76 })
        // Base64 never yields a line starting with a dot, so no dot-stuffing is needed.
        XCTAssertFalse(encodedLines.contains { $0.hasPrefix(".") })
        let decoded = Data(base64Encoded: encodedLines.joined()).flatMap { String(data: $0, encoding: .utf8) }
        XCTAssertEqual(decoded, body)
    }

    func testEmptyBodyRenders() throws {
        XCTAssertTrue(try message(body: "").rendered().hasSuffix("base64\r\n\r\n"))
    }

    func testNonAsciiSubjectIsEncoded() throws {
        let text = try message(subject: "Mum: daily summary — 2 alerts").rendered()
        XCTAssertTrue(text.contains("Subject: =?utf-8?B?"))
        XCTAssertFalse(text.contains("—"))
    }

    func testLongNonAsciiSubjectSplitsIntoShortEncodedWords() {
        let encoded = SMTPMessage.encodedHeader(String(repeating: "é", count: 60))
        let words = encoded.components(separatedBy: "\r\n ")
        XCTAssertGreaterThan(words.count, 1)
        XCTAssertTrue(words.allSatisfy { $0.count <= 75 })
    }

    func testHeaderInjectionIsRejected() {
        XCTAssertThrowsError(try message(subject: "Hi\r\nBcc: evil@example.com").rendered()) {
            XCTAssertEqual($0 as? SMTPError, .invalidField("subject"))
        }
        XCTAssertThrowsError(try message(to: "a@example.com\nRCPT TO:<x@y.z>").rendered()) {
            XCTAssertEqual($0 as? SMTPError, .invalidField("to"))
        }
    }

    func testMalformedAddressesAreRejected() {
        for bad in ["", "not-an-address", "a@b", "@example.com", "a b@example.com", "a@@example.com"] {
            XCTAssertThrowsError(try message(to: bad).rendered(), "accepted \(bad)")
        }
    }

    func testAddressExtraction() {
        XCTAssertEqual(SMTPMessage.address(in: "NOOP <noop@mg.example.com>"), "noop@mg.example.com")
        XCTAssertEqual(SMTPMessage.address(in: " plain@example.com "), "plain@example.com")
    }

    // MARK: - Reply parsing

    func testSingleLineReply() throws {
        var parser = SMTPReplyParser()
        XCTAssertEqual(try parser.append("220 smtp.example.com ESMTP\r\n"), [SMTPReply(code: 220, lines: ["smtp.example.com ESMTP"])])
    }

    func testMultiLineReplyAcrossChunks() throws {
        var parser = SMTPReplyParser()
        XCTAssertEqual(try parser.append("250-smtp.example.com\r\n250-AUTH PLA"), [])
        XCTAssertEqual(try parser.append("IN LOGIN\r\n250 SIZE 1000\r\n"),
                       [SMTPReply(code: 250, lines: ["smtp.example.com", "AUTH PLAIN LOGIN", "SIZE 1000"])])
    }

    func testTwoRepliesInOneChunk() throws {
        var parser = SMTPReplyParser()
        XCTAssertEqual(try parser.append("250 ok\r\n354 go\r\n").map(\.code), [250, 354])
    }

    func testCodeOnlyLine() throws {
        var parser = SMTPReplyParser()
        XCTAssertEqual(try parser.append("250\r\n"), [SMTPReply(code: 250, lines: [""])])
    }

    func testGarbageReplyThrows() {
        var parser = SMTPReplyParser()
        XCTAssertThrowsError(try parser.append("hello there\r\n"))
        var short = SMTPReplyParser()
        XCTAssertThrowsError(try short.append("25\r\n"))
    }

    // MARK: - Session

    func testHappyPath() throws {
        var session = try SMTPSession(username: "postmaster@mg.example.com", password: "s3cret", message: message())
        XCTAssertEqual(try session.next(after: reply(220)), .send("EHLO localhost\r\n"))
        let token = Data("\u{0}postmaster@mg.example.com\u{0}s3cret".utf8).base64EncodedString()
        XCTAssertEqual(try session.next(after: reply(250)), .send("AUTH PLAIN \(token)\r\n"))
        XCTAssertEqual(try session.next(after: reply(235)), .send("MAIL FROM:<noop@mg.example.com>\r\n"))
        XCTAssertEqual(try session.next(after: reply(250)), .send("RCPT TO:<rahul@example.com>\r\n"))
        XCTAssertEqual(try session.next(after: reply(250)), .send("DATA\r\n"))
        XCTAssertFalse(session.messageAccepted)
        guard case .send(let payload) = try session.next(after: reply(354)) else { return XCTFail("expected payload") }
        XCTAssertTrue(payload.hasSuffix("\r\n.\r\n"))
        XCTAssertFalse(session.messageAccepted)
        XCTAssertEqual(try session.next(after: reply(250)), .send("QUIT\r\n"))
        XCTAssertTrue(session.messageAccepted)
        XCTAssertEqual(try session.next(after: reply(221)), .finished)
    }

    func testAuthFailureNamesTheStageAndNeverThePassword() throws {
        var session = try SMTPSession(username: "u", password: "s3cret", message: message())
        _ = try session.next(after: reply(220))
        _ = try session.next(after: reply(250))
        XCTAssertThrowsError(try session.next(after: reply(535, "Authentication failed"))) { error in
            XCTAssertEqual(error as? SMTPError, .rejected(stage: "auth", code: 535, text: "Authentication failed"))
            XCTAssertFalse("\(error)".contains("s3cret"))
        }
    }

    func testRejectionAtEachStage() throws {
        let failAt: [(Int, [Int], String)] = [
            (554, [], "greeting"), (502, [220], "ehlo"), (550, [220, 250, 235], "mailFrom"),
            (550, [220, 250, 235, 250], "rcptTo"), (451, [220, 250, 235, 250, 250], "data"),
            (552, [220, 250, 235, 250, 250, 354], "body"),
        ]
        for (code, prefix, stage) in failAt {
            var session = try SMTPSession(username: "u", password: "p", message: message())
            for ok in prefix { _ = try session.next(after: reply(ok)) }
            XCTAssertThrowsError(try session.next(after: reply(code)), stage) {
                guard case .rejected(let got, let gotCode, _)? = $0 as? SMTPError else { return XCTFail("wrong error") }
                XCTAssertEqual(got, stage)
                XCTAssertEqual(gotCode, code)
            }
        }
    }

    func testRecipientForwardCodeIsAccepted() throws {
        var session = try SMTPSession(username: "u", password: "p", message: message())
        for ok in [220, 250, 235, 250] { _ = try session.next(after: reply(ok)) }
        XCTAssertEqual(try session.next(after: reply(251)), .send("DATA\r\n"))
    }

    func testCredentialsWithControlCharactersAreRejected() {
        XCTAssertThrowsError(try SMTPSession(username: "u\r\n", password: "p", message: message()))
        XCTAssertThrowsError(try SMTPSession(username: "u", password: "", message: message()))
    }
}
