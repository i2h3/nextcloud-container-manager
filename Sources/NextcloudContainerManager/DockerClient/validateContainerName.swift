// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

///
/// Verify that a requested container name is one the Docker Engine accepts, so that a deployment which requested it fails before any image is pulled rather than with a Docker error about the name.
///
/// The Docker Engine restricts container names to `[a-zA-Z0-9][a-zA-Z0-9_.-]+`, which means at least two characters, an alphanumeric first one and only ASCII letters, digits, underscores, periods and hyphens afterwards. Names within that character set need no percent-encoding, so ``NextcloudContainerManager/deploy(configuration:)`` can pass a validated name straight into the query string of `POST /containers/create`.
///
/// - Parameters:
///     - name: The container name to verify.
///
/// - Throws: ``NextcloudContainerManagerError/invalidContainerName(_:)`` when the name does not match what the Docker Engine accepts.
///
func validateContainerName(_ name: String) throws {
    func isAlphanumeric(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber)
    }

    guard name.count >= 2, let first = name.first, isAlphanumeric(first) else {
        throw NextcloudContainerManagerError.invalidContainerName(name)
    }

    guard name.dropFirst().allSatisfy({ isAlphanumeric($0) || $0 == "_" || $0 == "." || $0 == "-" }) else {
        throw NextcloudContainerManagerError.invalidContainerName(name)
    }
}
