// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

///
/// Errors that can be thrown when communicating with the Docker Engine API.
///
enum DockerClientError: Error {
    /// The kernel could not assign a free TCP port.
    case couldNotFindFreePort
    /// The raw HTTP response from the Docker daemon could not be parsed.
    case invalidResponse
    /// The Docker daemon returned an unexpected HTTP status code.
    case unexpectedStatusCode(Int, String)
    /// A command executed inside the container exited with a non-zero status.
    case commandFailed(command: [String], exitCode: Int)
    /// The Nextcloud instance did not become ready within the expected time.
    case timeout
    /// The Docker Engine Unix domain socket was not found at the given path.
    case socketNotFound(String)
}
