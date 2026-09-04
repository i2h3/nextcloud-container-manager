// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

///
/// Errors that can be thrown when communicating with the Docker Engine API.
///
enum DockerClientError: Error {
    ///
    /// The kernel could not assign a free TCP port.
    ///
    case couldNotFindFreePort

    ///
    /// The raw HTTP response from the Docker daemon could not be parsed.
    ///
    case invalidResponse

    ///
    /// The Docker daemon returned an unexpected HTTP status code.
    ///
    case unexpectedStatusCode(Int, String)

    ///
    /// Pulling an image from its registry failed. The associated values are the image reference and the error the Docker Engine reported inside the pull stream.
    ///
    case imagePullFailed(image: String, message: String)

    ///
    /// The Docker Engine accepted a request but then went quiet for longer than the request allowed.
    ///
    /// The associated value is the request path. This is what a stalled daemon looks like from here: the socket stays open with nothing arriving on it, which without a deadline would leave the call waiting forever.
    ///
    case requestTimedOut(path: String)

    ///
    /// Something that is waited on did not happen within the expected time.
    ///
    /// This covers the Nextcloud instance not becoming ready after deployment, the push endpoint not answering, and the Docker Engine not recording a command's exit status in the moment after its output stream closed. A command overrunning the allowance given to it is not this — that is ``NextcloudContainerManagerError/commandTimedOut(command:)``.
    ///
    case timeout

    ///
    /// The Docker Engine Unix domain socket was not found at the given path.
    ///
    case socketNotFound(String)
}
