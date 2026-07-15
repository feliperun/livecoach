import Foundation

struct DeepgramSocketConnection: Sendable {
    let socket: URLSessionWebSocketTask
    let session: URLSession
}

enum DeepgramSocketConnector {
    static func connect(config: SttConfig, apiKey: String) async throws -> DeepgramSocketConnection {
        var request = URLRequest(url: try DeepgramLiveRequest.url(config: config))
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        let delegate = DeepgramWebSocketDelegate()
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        let socket = session.webSocketTask(with: request)
        socket.resume()
        do {
            try await waitForOpen(delegate.opened)
            return .init(socket: socket, session: session)
        } catch {
            socket.cancel(with: .goingAway, reason: nil)
            session.invalidateAndCancel()
            throw DeepgramError.connectionFailed
        }
    }

    private static func waitForOpen(_ opened: AsyncThrowingStream<Void, Error>) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for try await _ in opened { return }
                throw DeepgramError.connectionFailed
            }
            group.addTask {
                try await Task.sleep(for: .seconds(8))
                throw DeepgramError.connectionFailed
            }
            guard let result = try await group.next() else { throw DeepgramError.connectionFailed }
            group.cancelAll()
            return result
        }
    }
}

private final class DeepgramWebSocketDelegate: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    let opened: AsyncThrowingStream<Void, Error>
    private let continuation: AsyncThrowingStream<Void, Error>.Continuation

    override init() {
        let pair = AsyncThrowingStream<Void, Error>.makeStream()
        self.opened = pair.stream
        self.continuation = pair.continuation
        super.init()
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        continuation.yield(())
        continuation.finish()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        if let error { continuation.finish(throwing: error) }
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        if closeCode != .normalClosure {
            continuation.finish(throwing: DeepgramError.connectionFailed)
        }
    }
}
