import Darwin

///
/// Ask the kernel for a free TCP port by binding to port 0, reading back the
/// assigned port, and then immediately releasing the socket.
///
/// There is a small TOCTOU window between releasing the socket and Docker
/// binding to the port, which is acceptable for test-container use.
///
/// - Returns: A free port number on the local host.
/// - Throws: ``DockerClientError/couldNotFindFreePort`` when the kernel does
///   not grant a socket or assign a port.
///
func findFreePort() throws -> UInt16 {
    let sock = Darwin.socket(AF_INET, SOCK_STREAM, 0)
    guard sock >= 0 else {
        throw DockerClientError.couldNotFindFreePort
    }
    defer { Darwin.close(sock) }

    var addr = sockaddr_in()
    addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = 0
    addr.sin_addr = in_addr(s_addr: INADDR_ANY)

    let bindResult = withUnsafeMutablePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard bindResult == 0 else {
        throw DockerClientError.couldNotFindFreePort
    }

    var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
    let nameResult = withUnsafeMutablePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.getsockname(sock, $0, &addrLen)
        }
    }
    guard nameResult == 0 else {
        throw DockerClientError.couldNotFindFreePort
    }

    return addr.sin_port.bigEndian
}
