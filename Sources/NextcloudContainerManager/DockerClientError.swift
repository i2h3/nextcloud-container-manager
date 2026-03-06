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
}
