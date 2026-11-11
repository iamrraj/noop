import Foundation
import Network
import StrandAnalytics

/// Sends one email over an implicit-TLS SMTP connection. The conversation itself is `SMTPSession`
/// (pure, unit-tested in StrandAnalytics); this type only carries bytes between it and the socket.
enum SMTPTransport {

    enum TransportError: Error, Equatable {
        case timedOut
        case connectionFailed(String)
        case closedByServer
    }

    /// Kept under the ~30 s iOS grants a background refresh, so a stalled server cannot run the task
    /// into its expiration handler.
    static let timeoutSeconds: UInt64 = 20

    static func send(config: CareConfig, email: CareEmail, now: Date = Date()) async throws {
        let message = SMTPMessage(from: config.from, to: config.to, subject: email.subject, body: email.body,
                                  date: now, messageId: "\(UUID().uuidString.lowercased())@noop.local")
        let session = try SMTPSession(username: config.username, password: config.password, message: message)
        guard let port = NWEndpoint.Port(rawValue: config.port) else {
            throw TransportError.connectionFailed("invalid port")
        }
        let link = Link(connection: NWConnection(host: NWEndpoint.Host(config.host), port: port, using: .tls))

        try await withThrowingTaskGroup(of: Void.self) { group in
            // Cancelling the connection is what unblocks a receive that is parked on a silent server.
            defer { group.cancelAll(); link.cancel() }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                throw TransportError.timedOut
            }
            group.addTask {
                var live = session
                try await converse(link: link, session: &live)
            }
            try await group.next()
        }
    }

    private static func converse(link: Link, session: inout SMTPSession) async throws {
        try await link.start()
        var parser = SMTPReplyParser()
        while true {
            let text: String
            do {
                text = try await link.receive()
            } catch {
                // Some servers drop the connection straight after accepting the message, before
                // answering QUIT. The message is delivered, so that is success, not a failure to retry.
                if session.messageAccepted { return }
                throw error
            }
            for reply in try parser.append(text) {
                switch try session.next(after: reply) {
                case .send(let command): try await link.send(command)
                case .finished: return
                }
            }
        }
    }

    /// Async wrapper over one `NWConnection`.
    private final class Link: @unchecked Sendable {
        private let connection: NWConnection
        private let queue = DispatchQueue(label: "noop.care.smtp")

        init(connection: NWConnection) { self.connection = connection }

        func cancel() { connection.cancel() }

        func start() async throws {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let once = ResumeOnce()
                connection.stateUpdateHandler = { [connection] state in
                    // The handler runs on `queue`, one call at a time.
                    guard !once.resumed else { return }
                    switch state {
                    case .ready:
                        once.resumed = true
                        connection.stateUpdateHandler = nil
                        continuation.resume()
                    case .failed(let error), .waiting(let error):
                        once.resumed = true
                        connection.stateUpdateHandler = nil
                        connection.cancel()
                        continuation.resume(throwing: TransportError.connectionFailed(error.localizedDescription))
                    case .cancelled:
                        once.resumed = true
                        continuation.resume(throwing: TransportError.timedOut)
                    default:
                        break
                    }
                }
                connection.start(queue: queue)
            }
        }

        /// Whether `start()`'s continuation has been resumed. Only touched on `queue`.
        private final class ResumeOnce: @unchecked Sendable { var resumed = false }

        func send(_ text: String) async throws {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connection.send(content: Data(text.utf8), completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: TransportError.connectionFailed(error.localizedDescription))
                    } else {
                        continuation.resume()
                    }
                })
            }
        }

        func receive() async throws -> String {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, isComplete, error in
                    if let data, !data.isEmpty {
                        continuation.resume(returning: String(decoding: data, as: UTF8.self))
                    } else if let error {
                        continuation.resume(throwing: TransportError.connectionFailed(error.localizedDescription))
                    } else if isComplete {
                        continuation.resume(throwing: TransportError.closedByServer)
                    } else {
                        continuation.resume(returning: "")
                    }
                }
            }
        }
    }
}
