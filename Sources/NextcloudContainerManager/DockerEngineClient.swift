import Foundation

///
/// Minimal HTTP/1.1 client that speaks to the Docker Engine API
/// over the Unix domain socket that Docker Desktop exposes on macOS.
///
/// Uses POSIX sockets directly; `NWConnection` cannot drive a Unix-domain
/// socket with TCP parameters on macOS and fails with `ENETDOWN`.
///
struct DockerEngineClient: Sendable {
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
    /// Send a `GET` request with no body.
    ///
    func get(path: String) async throws -> (statusCode: Int, body: Data) {
        try await send(method: "GET", path: path, body: nil)
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
            if let body {
                d.append(body)
            }
            return d
        }()

        let socketPath = self.socketPath // capture value, not self

        return try await withCheckedThrowingContinuation { continuation in
            // Dispatch to a GCD thread so the blocking POSIX calls
            // don't stall the Swift concurrency cooperative thread pool.
            DispatchQueue.global(qos: .utility).async {
                do {
                    let result = try dockerSocketRequest(socketPath: socketPath, requestData: requestData)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// MARK: - POSIX-socket transport (file-private free functions)

private func dockerSocketRequest(
    socketPath: String,
    requestData: Data
) throws -> (statusCode: Int, body: Data) {
    // ── 1. Open a Unix-domain stream socket ─────────────────────────────────
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    defer { close(fd) }

    // ── 2. Connect to the Docker socket path ─────────────────────────────────
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    socketPath.withCString { src in
        withUnsafeMutableBytes(of: &addr.sun_path) { bytes in
            _ = memcpy(bytes.baseAddress!, src, strlen(src) + 1)
        }
    }
    let connectResult = withUnsafePointer(to: &addr) { addrPtr in
        addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard connectResult == 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }

    // ── 3. Send the full HTTP request ────────────────────────────────────────
    var totalSent = 0
    while totalSent < requestData.count {
        let sent = requestData.withUnsafeBytes { ptr in
            send(fd, ptr.baseAddress!.advanced(by: totalSent), ptr.count - totalSent, 0)
        }
        guard sent > 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        totalSent += sent
    }

    // ── 4. Read until the server closes the connection (Connection: close) ───
    var responseData = Data()
    var buffer = [UInt8](repeating: 0, count: 8192)
    while true {
        let n = buffer.withUnsafeMutableBytes { ptr in
            recv(fd, ptr.baseAddress!, ptr.count, 0)
        }
        if n <= 0 {
            break
        }
        responseData.append(buffer, count: n)
    }

    // ── 5. Parse the HTTP response ───────────────────────────────────────────
    guard let parsed = parseHTTPResponse(responseData) else {
        throw DockerClientError.invalidResponse
    }
    return parsed
}

private func parseHTTPResponse(_ data: Data) -> (statusCode: Int, body: Data)? {
    guard let separatorRange = data.range(of: Data("\r\n\r\n".utf8)) else {
        return nil
    }

    let headerData = data[..<separatorRange.lowerBound]
    var body = Data(data[separatorRange.upperBound...])

    guard
        let headerText = String(data: headerData, encoding: .utf8),
        let statusLine = headerText.components(separatedBy: "\r\n").first
    else {
        return nil
    }

    // "HTTP/1.1 201 Created"
    let parts = statusLine.split(separator: " ", maxSplits: 2)
    guard parts.count >= 2, let statusCode = Int(parts[1]) else {
        return nil
    }

    if headerText.lowercased().contains("transfer-encoding: chunked") {
        body = decodeChunked(body)
    }

    return (statusCode: statusCode, body: body)
}

private func decodeChunked(_ data: Data) -> Data {
    var result = Data()
    var position = data.startIndex
    let crlf = Data("\r\n".utf8)

    while position < data.endIndex {
        guard let crlfRange = data[position...].range(of: crlf) else {
            break
        }

        let sizeHex = data[position ..< crlfRange.lowerBound]
        guard
            let sizeString = String(data: sizeHex, encoding: .ascii),
            let chunkSize = Int(sizeString.trimmingCharacters(in: .whitespaces), radix: 16),
            chunkSize > 0
        else {
            break
        }

        let chunkStart = crlfRange.upperBound
        guard let chunkEnd = data.index(chunkStart, offsetBy: chunkSize, limitedBy: data.endIndex) else {
            break
        }
        result.append(data[chunkStart ..< chunkEnd])
        position = data.index(chunkEnd, offsetBy: 2, limitedBy: data.endIndex) ?? data.endIndex
    }

    return result
}
