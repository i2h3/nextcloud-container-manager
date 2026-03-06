import Foundation
import Network
import Synchronization

///
/// Minimal HTTP/1.1 client that speaks to the Docker Engine API
/// over the Unix domain socket that Docker Desktop exposes on macOS.
///
struct DockerEngineClient {
    /// The file-system path to the Docker Engine Unix domain socket.
    let socketPath: String

    ///
    /// Create a new client.
    ///
    /// - Parameters:
    ///     - socketPath: Defaults to the standard Docker Desktop socket location.
    ///
    init(socketPath: String = "/var/run/docker.sock") {
        self.socketPath = socketPath
    }

    // MARK: - Convenience helpers

    ///
    /// Send a `POST` request with a JSON-encoded body.
    ///
    func post<RequestBody: Encodable>(path: String, body: RequestBody) async throws -> (statusCode: Int, body: Data) {
        let data = try JSONEncoder().encode(body)
        return try await send(method: "POST", path: path, body: data)
    }

    ///
    /// Send a `POST` request with no body.
    ///
    func post(path: String) async throws -> (statusCode: Int, body: Data) {
        try await send(method: "POST", path: path, body: nil)
    }

    ///
    /// Send a `DELETE` request with no body.
    ///
    func delete(path: String) async throws -> (statusCode: Int, body: Data) {
        try await send(method: "DELETE", path: path, body: nil)
    }

    // MARK: - Core send

    private func send(method: String, path: String, body: Data?) async throws -> (statusCode: Int, body: Data) {
        var requestText = "\(method) \(path) HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n"
        if let body {
            requestText += "Content-Type: application/json\r\nContent-Length: \(body.count)\r\n"
        }
        requestText += "\r\n"

        // Build as a let so it is safe to capture in @Sendable closures.
        let requestData: Data = {
            var d = Data(requestText.utf8)
            if let body { d.append(body) }
            return d
        }()

        let socketPath = self.socketPath // capture value, not self

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(statusCode: Int, body: Data), Error>) in
            let connection = NWConnection(to: .unix(path: socketPath), using: .tcp)

            // Mutex-protected flag ensures continuation.resume is called exactly once
            // even if NWConnection delivers overlapping state/send callbacks.
            let done = Mutex<Bool>(false)

            @Sendable func resumeOnce(with result: Result<(statusCode: Int, body: Data), Error>) {
                let shouldResume = done.withLock { flag -> Bool in
                    guard !flag else { return false }
                    flag = true
                    return true
                }
                guard shouldResume else { return }
                connection.cancel()
                continuation.resume(with: result)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: requestData, completion: .contentProcessed { error in
                        if let error {
                            resumeOnce(with: .failure(error))
                            return
                        }
                        receiveAll(connection: connection, accumulated: Data()) { result in
                            switch result {
                            case let .success(responseData):
                                if let parsed = parseHTTPResponse(responseData) {
                                    resumeOnce(with: .success(parsed))
                                } else {
                                    resumeOnce(with: .failure(DockerClientError.invalidResponse))
                                }
                            case let .failure(err):
                                resumeOnce(with: .failure(err))
                            }
                        }
                    })
                case let .failed(error):
                    resumeOnce(with: .failure(error))
                case .cancelled, .setup, .preparing, .waiting:
                    break
                @unknown default:
                    break
                }
            }

            connection.start(queue: .global(qos: .utility))
        }
    }
}

// MARK: - Private helpers (file-private free functions)

private func receiveAll(
    connection: NWConnection,
    accumulated: Data,
    completion: @escaping @Sendable (Result<Data, Error>) -> Void
) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
        var updated = accumulated
        if let data { updated.append(data) }

        if let error {
            completion(.failure(error))
        } else if isComplete {
            completion(.success(updated))
        } else {
            receiveAll(connection: connection, accumulated: updated, completion: completion)
        }
    }
}

private func parseHTTPResponse(_ data: Data) -> (statusCode: Int, body: Data)? {
    guard let separatorRange = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }

    let headerData = data[..<separatorRange.lowerBound]
    let body = Data(data[separatorRange.upperBound...])

    guard
        let headerText = String(data: headerData, encoding: .utf8),
        let statusLine = headerText.components(separatedBy: "\r\n").first
    else { return nil }

    // "HTTP/1.1 201 Created"
    let parts = statusLine.split(separator: " ", maxSplits: 2)
    guard parts.count >= 2, let statusCode = Int(parts[1]) else { return nil }

    return (statusCode: statusCode, body: body)
}
