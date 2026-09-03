// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Splits a multiplexed Docker stream into the standard output and standard error it carries.
///
/// Containers created without a pseudo-terminal — as every container this package deploys is — have their output multiplexed by the Docker Engine, so endpoints such as `GET /containers/{id}/logs` answer with a sequence of frames rather than with plain text. Each frame is an eight byte header, holding the stream indicator in its first byte and the payload length as a big-endian 32-bit integer in its last four, followed by the payload itself. A stream from a container created with a pseudo-terminal carries no such headers and must not be passed here.
///
/// Trailing bytes that do not form a complete frame are ignored, so a truncated stream yields everything that was received in full rather than an error.
///
/// - Parameters:
///     - data: The multiplexed stream.
///
/// - Returns: The payloads of the standard output and standard error frames, each concatenated in the order they were received.
///
func demultiplexDockerStream(_ data: Data) -> (standardOutput: Data, standardError: Data) {
    var standardOutput = Data()
    var standardError = Data()
    var position = data.startIndex

    while let headerEnd = data.index(position, offsetBy: 8, limitedBy: data.endIndex) {
        let header = data[position ..< headerEnd]
        let size = header.suffix(4).reduce(0) { $0 << 8 | Int($1) }

        guard let payloadEnd = data.index(headerEnd, offsetBy: size, limitedBy: data.endIndex) else {
            break
        }

        switch header[header.startIndex] {
            case 1:
                standardOutput.append(data[headerEnd ..< payloadEnd])
            case 2:
                standardError.append(data[headerEnd ..< payloadEnd])
            default:
                break
        }

        position = payloadEnd
    }

    return (standardOutput, standardError)
}
