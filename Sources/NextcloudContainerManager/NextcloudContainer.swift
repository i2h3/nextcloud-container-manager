///
/// The interface of an individual test container deployment representation.
///
public struct NextcloudContainer: Identifiable, Sendable {
    ///
    /// The initial configuration this container was created with.
    ///
    public let configuration: NextcloudConfiguration

    ///
    /// The unique Docker container identifier.
    ///
    public let id: String

    ///
    /// The host port mapped to the container's HTTP port 80.
    ///
    public let port: UInt

    /// The Docker Engine client used to communicate with the daemon.
    let client: DockerEngineClient

    ///
    /// Stops the container and deletes all associated data.
    ///
    /// Because the container was created with `AutoRemove`, stopping it is
    /// sufficient — Docker removes it automatically once it exits.
    ///
    public func delete() async throws {
        // Acceptable status codes:
        //   204 – successfully stopped
        //   304 – container was already stopped (already auto-removed)
        //   404 – container no longer exists (already removed)
        let response = try await client.post(path: "/containers/\(id)/stop")
        guard [204, 304, 404].contains(response.statusCode) else {
            let message = String(data: response.body, encoding: .utf8) ?? "<no body>"
            throw DockerClientError.unexpectedStatusCode(response.statusCode, message)
        }
    }
}
