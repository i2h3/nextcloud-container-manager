// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Darwin

///
/// Verify that a host port can be bound, so that a deployment which requested it fails with a clear reason rather than with a Docker error about a port binding.
///
/// The check binds the port and releases it again, which leaves the same small window between the check and Docker binding it as ``findFreePort()`` does. That is acceptable for the throwaway containers this package deploys.
///
/// - Parameters:
///     - port: The port to verify.
///
/// - Throws: ``NextcloudContainerManagerError/portUnavailable(_:)`` when the port cannot be bound.
///
func ensurePortIsFree(_ port: UInt16) throws {
    let sock = Darwin.socket(AF_INET, SOCK_STREAM, 0)

    guard sock >= 0 else {
        throw NextcloudContainerManagerError.portUnavailable(port)
    }

    defer { Darwin.close(sock) }

    var addr = sockaddr_in()
    addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = port.bigEndian
    addr.sin_addr = in_addr(s_addr: INADDR_ANY)

    let bindResult = withUnsafeMutablePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }

    guard bindResult == 0 else {
        throw NextcloudContainerManagerError.portUnavailable(port)
    }
}
