// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Extract the contents of the first file entry from a tar archive.
///
/// The Docker Engine `GET /containers/{id}/archive` endpoint returns the requested path packed into a tar archive, which is the mechanism behind `docker cp`. ``NextcloudContainerManager/logFile(inContainer:)`` requests a single file, so this function reads just the first entry: it parses the 512-byte header to find the payload size — twelve octal-ASCII bytes at offset 124, terminated by a space or null — and returns the bytes that follow. The archive's trailing padding and any further entries are ignored.
///
/// - Parameters:
///     - data: The raw tar archive returned by the archive endpoint.
///
/// - Returns: The contents of the first file entry, or `nil` when the data is too short to contain a header or the size field cannot be parsed. An entry of length zero yields empty data.
///
func firstFileInTarArchive(_ data: Data) -> Data? {
    let headerSize = 512
    let sizeFieldOffset = 124
    let sizeFieldLength = 12

    guard data.count >= headerSize else {
        return nil
    }

    let headerStart = data.startIndex
    let sizeStart = data.index(headerStart, offsetBy: sizeFieldOffset)
    let sizeEnd = data.index(sizeStart, offsetBy: sizeFieldLength)
    let sizeField = String(decoding: data[sizeStart ..< sizeEnd], as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: " \0"))

    guard let size = Int(sizeField, radix: 8) else {
        return nil
    }

    let contentStart = data.index(headerStart, offsetBy: headerSize)

    guard let contentEnd = data.index(contentStart, offsetBy: size, limitedBy: data.endIndex) else {
        return nil
    }

    return data[contentStart ..< contentEnd]
}
