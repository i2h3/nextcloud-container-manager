// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Minimal HTTP/1.1 client that speaks to the Docker Engine API over the Unix domain socket that Docker Desktop exposes on macOS.
///
/// Uses POSIX sockets directly; `NWConnection` cannot drive a Unix-domain socket with TCP parameters on macOS and fails with `ENETDOWN`.
///
/// Every request is bounded. The Docker Engine answers a request by streaming until it closes the connection, and it has been observed to stop doing either — leaving a call that never returns and a thread that never comes back. Each request therefore carries a timeout, applied to the connect, to every send and to every receive, so a silent daemon surfaces as ``NextcloudContainerManagerError/engineRequestTimedOut(path:)`` instead of as a hang. Cancelling the surrounding task is the other way out: a blocked call cannot observe that by itself, so the socket is shut down through ``CancellableSocket`` to wake it, and the request ends as a `CancellationError`.
///
struct DockerEngineClient {
    ///
    /// How long a request tolerates silence from the Docker Engine when it does not ask for something else.
    ///
    /// The bound is on the gap between bytes rather than on the whole request, because the responses this client reads have no length known in advance: an image pull streams progress for as long as it takes, and an attached command streams output until it exits. What separates those from a stalled daemon is not how long they last but whether anything is still arriving.
    ///
    static let defaultRequestTimeout: TimeInterval = 60

    ///
    /// The file-system path to the Docker Engine Unix domain socket.
    ///
    let socketPath: String

    ///
    /// Create a new client.
    ///
    /// - Parameters:
    ///     - socketPath: Defaults to the standard Docker Desktop socket location.
    ///
    init(socketPath: String = "/var/run/docker.sock") throws {
        guard FileManager.default.fileExists(atPath: socketPath) else {
            throw NextcloudContainerManagerError.dockerEngineUnavailable(socketPath: socketPath)
        }

        self.socketPath = socketPath
    }

    // MARK: - Convenience helpers

    ///
    /// Send a `POST` request with a JSON-encoded body.
    ///
    func post(path: String, body: some Encodable, timeout: TimeInterval? = defaultRequestTimeout) async throws -> EngineResponse {
        let data = try JSONEncoder().encode(body)
        return try await send(method: "POST", path: path, body: data, timeout: timeout)
    }

    ///
    /// Send a `POST` request with no body.
    ///
    func post(path: String, timeout: TimeInterval? = defaultRequestTimeout) async throws -> EngineResponse {
        try await send(method: "POST", path: path, body: nil, timeout: timeout)
    }

    ///
    /// Send a `GET` request with no body.
    ///
    func get(path: String, timeout: TimeInterval? = defaultRequestTimeout) async throws -> EngineResponse {
        try await send(method: "GET", path: path, body: nil, timeout: timeout)
    }

    ///
    /// Send a `DELETE` request with no body.
    ///
    func delete(path: String, timeout: TimeInterval? = defaultRequestTimeout) async throws -> EngineResponse {
        try await send(method: "DELETE", path: path, body: nil, timeout: timeout)
    }

    // MARK: - Core send

    private func send(method: String, path: String, body: Data?, timeout: TimeInterval?) async throws -> EngineResponse {
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

        let socketPath = socketPath // capture value, not self

        // The blocking calls below cannot observe task cancellation on their own, so the socket is handed to the cancellation handler, which shuts it down to wake them.
        let socket = CancellableSocket()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // Dispatch to a GCD thread so the blocking POSIX calls
                // don't stall the Swift concurrency cooperative thread pool.
                DispatchQueue.global(qos: .utility).async {
                    do {
                        let result = try dockerSocketRequest(socketPath: socketPath, path: path, requestData: requestData, timeout: timeout, socket: socket)
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            socket.cancel()
        }
    }
}

// MARK: - POSIX-socket transport (file-private free functions)

///
/// Applies a timeout to everything the socket blocks on.
///
/// A `timeval` of zero means "no timeout" to the kernel, and an interval that is not a finite positive number cannot be expressed as one at all, so both are left as the unbounded blocking the socket already has — which is what a caller asking for no deadline wants.
///
private func applySocketTimeout(_ fileDescriptor: Int32, _ timeout: TimeInterval?) throws {
    guard let timeout, timeout.isFinite, timeout > 0 else {
        return
    }

    let bounded = min(timeout, TimeInterval(Int32.max))
    let seconds = bounded.rounded(.down)
    var interval = timeval(tv_sec: Int(seconds), tv_usec: suseconds_t((bounded - seconds) * 1_000_000))

    // Every deadline this client offers rests on these two options being installed, so a refusal is reported rather than discarded: carrying on would leave the socket blocking forever while the caller believes it is bounded.
    for option in [SO_RCVTIMEO, SO_SNDTIMEO] {
        let applied = withUnsafePointer(to: &interval) { pointer in
            setsockopt(fileDescriptor, SOL_SOCKET, option, pointer, socklen_t(MemoryLayout<timeval>.size))
        }

        guard applied == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }
}

///
/// Connects the socket, giving up once the timeout has passed.
///
/// The connect is performed non-blocking and waited on with `poll`, because a receive timeout does not cover establishing the connection: a socket file that exists but has nobody listening on it would otherwise block here rather than at the first read.
///
private func connectSocket(_ fileDescriptor: Int32, to address: inout sockaddr_un, path: String, timeout: TimeInterval?) throws {
    let flags = fcntl(fileDescriptor, F_GETFL, 0)
    _ = fcntl(fileDescriptor, F_SETFL, flags | O_NONBLOCK)

    defer { _ = fcntl(fileDescriptor, F_SETFL, flags) }

    let result = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fileDescriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }

    if result == 0 {
        return
    }

    guard errno == EINPROGRESS else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }

    var descriptor = pollfd(fd: fileDescriptor, events: Int16(POLLOUT), revents: 0)
    let deadline = timeout.flatMap { $0.isFinite && $0 > 0 ? Date().addingTimeInterval($0) : nil }
    var ready: Int32

    // A signal arriving mid-wait is not a failed connection, so the wait is resumed rather than reported — against what is left of the deadline, so that being interrupted cannot extend it.
    repeat {
        let milliseconds: Int32 = deadline.map { Int32(min(max(0, $0.timeIntervalSinceNow) * 1000, TimeInterval(Int32.max))) } ?? -1
        ready = poll(&descriptor, 1, milliseconds)
    } while ready < 0 && errno == EINTR

    if ready == 0 {
        throw NextcloudContainerManagerError.engineRequestTimedOut(path: path)
    }

    guard ready > 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }

    var pending: Int32 = 0
    var size = socklen_t(MemoryLayout<Int32>.size)
    _ = getsockopt(fileDescriptor, SOL_SOCKET, SO_ERROR, &pending, &size)

    guard pending == 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(pending))
    }
}

private func dockerSocketRequest(socketPath: String, path: String, requestData: Data, timeout: TimeInterval?, socket cancellation: CancellableSocket) throws -> EngineResponse {
    // ── 1. Open a Unix-domain stream socket ─────────────────────────────────
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)

    guard fd >= 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }

    // Cancelling shuts this socket down while a send may still be in flight, and sending on a socket that has been shut down raises SIGPIPE, which by default kills the whole process instead of failing the call. Asking the socket to report the condition as an error keeps a cancelled request a failed request, and a refusal is fatal to the request rather than ignored, because carrying on would risk the process itself.
    var reportBrokenPipeAsError: Int32 = 1

    guard setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &reportBrokenPipeAsError, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }

    // The descriptor is given up before it is closed, so a cancellation that arrives late finds nothing to shut down rather than a number the kernel has reissued.
    defer {
        cancellation.release()
        close(fd)
    }

    guard cancellation.adopt(fd) else {
        throw CancellationError()
    }

    // ── 2. Connect to the Docker socket path ─────────────────────────────────
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    socketPath.withCString { src in
        withUnsafeMutableBytes(of: &addr.sun_path) { bytes in
            _ = memcpy(bytes.baseAddress!, src, strlen(src) + 1)
        }
    }

    try connectSocket(fd, to: &addr, path: path, timeout: timeout)
    try applySocketTimeout(fd, timeout)

    // ── 3. Send the full HTTP request ────────────────────────────────────────
    var totalSent = 0

    while totalSent < requestData.count {
        let sent = requestData.withUnsafeBytes { ptr in
            send(fd, ptr.baseAddress!.advanced(by: totalSent), ptr.count - totalSent, 0)
        }

        if sent > 0 {
            totalSent += sent

            continue
        }

        // A shutdown from the cancellation handler surfaces here as an ordinary failure, so cancellation is checked before the errno is interpreted.
        if cancellation.isCancelled {
            throw CancellationError()
        }

        // A send that reports no progress is either an interruption to retry, the timeout expiring, or a genuine failure — telling them apart is what keeps a stalled daemon from looking like a truncated request.
        switch errno {
            case EINTR:
                continue
            case EAGAIN, EWOULDBLOCK:
                throw NextcloudContainerManagerError.engineRequestTimedOut(path: path)
            default:
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    // ── 4. Read until the server closes the connection (Connection: close) ───
    var responseData = Data()
    var buffer = [UInt8](repeating: 0, count: 8192)

    while true {
        // Reading until the peer hangs up is only correct while it does hang up. When a response carries its own length — a Content-Length, a terminating chunk, or a status defined to have no body — waiting for a close that may never come would turn a complete answer into a timeout. The Docker Engine does close today, because this client asks it to, and round trips were measured at the same speed either way; this is about not depending on it.
        if httpResponseIsComplete(responseData) {
            break
        }

        let received = buffer.withUnsafeMutableBytes { ptr in
            recv(fd, ptr.baseAddress!, ptr.count, 0)
        }

        if received > 0 {
            responseData.append(buffer, count: received)

            continue
        }

        // A shutdown from the cancellation handler ends the read, and it does so as an orderly close, so cancellation has to be ruled out before a zero is believed — otherwise an interrupted request would hand back whatever had arrived so far as if it were the whole response.
        if cancellation.isCancelled {
            throw CancellationError()
        }

        // Zero is the orderly close that ends every response; anything else has to be distinguished the same way as on the sending side, because treating a timeout as the end of the body would hand back a half-read response as if it were complete.
        if received == 0 {
            break
        }

        switch errno {
            case EINTR:
                continue
            case EAGAIN, EWOULDBLOCK:
                throw NextcloudContainerManagerError.engineRequestTimedOut(path: path)
            default:
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    // ── 5. Parse the HTTP response ───────────────────────────────────────────
    guard let parsed = parseHTTPResponse(responseData, path: path) else {
        throw NextcloudContainerManagerError.engineResponseUnreadable(path: path)
    }

    return parsed
}

///
/// Whether the bytes received so far are a whole HTTP response.
///
/// The Docker Engine frames its answers three ways: a `Content-Length`, a chunked body ending in a zero-length chunk, and a status that is defined to carry no body at all. An attached command stream is the fourth case and carries none of them — it ends when the command does — so a response whose framing cannot be read is reported as incomplete and left to the connection to finish.
///
/// - Parameters:
///     - data: Everything received on the socket so far.
///
/// - Returns: Whether reading can stop without waiting for the peer to close.
///
private func httpResponseIsComplete(_ data: Data) -> Bool {
    guard let separator = data.range(of: Data("\r\n\r\n".utf8)) else {
        return false
    }

    guard let headerText = String(data: data[..<separator.lowerBound], encoding: .utf8) else {
        return false
    }

    let lines = headerText.components(separatedBy: "\r\n")
    let body = data[separator.upperBound...]

    // 204 and 304 are defined to carry no body, so their headers are the whole answer.
    if let statusLine = lines.first {
        let parts = statusLine.split(separator: " ", maxSplits: 2)

        if parts.count >= 2, let statusCode = Int(parts[1]), statusCode == 204 || statusCode == 304 {
            return true
        }
    }

    if headerText.lowercased().contains("transfer-encoding: chunked") {
        return chunkedBodyIsComplete(body)
    }

    for line in lines.dropFirst() {
        let pieces = line.split(separator: ":", maxSplits: 1)

        guard pieces.count == 2, pieces[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" else {
            continue
        }

        guard let length = Int(pieces[1].trimmingCharacters(in: .whitespaces)) else {
            return false
        }

        return body.count >= length
    }

    return false
}

///
/// Whether a chunked body has reached its terminating zero-length chunk.
///
/// - Parameters:
///     - body: The body received so far, starting at its first chunk header.
///
/// - Returns: Whether the terminating chunk has arrived.
///
private func chunkedBodyIsComplete(_ body: Data) -> Bool {
    var position = body.startIndex
    let crlf = Data("\r\n".utf8)

    while position < body.endIndex {
        guard let lineEnd = body[position...].range(of: crlf) else {
            return false
        }

        guard let text = String(data: body[position ..< lineEnd.lowerBound], encoding: .ascii) else {
            return false
        }

        // A chunk header may carry extensions after a semicolon, which are not part of the size.
        let sizeText = text.split(separator: ";").first.map(String.init) ?? text

        guard let size = Int(sizeText.trimmingCharacters(in: .whitespaces), radix: 16) else {
            return false
        }

        if size == 0 {
            return true
        }

        guard let next = body.index(lineEnd.upperBound, offsetBy: size + 2, limitedBy: body.endIndex) else {
            return false
        }

        position = next
    }

    return false
}

private func parseHTTPResponse(_ data: Data, path: String) -> EngineResponse? {
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

    return EngineResponse(path: path, statusCode: statusCode, body: body)
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
