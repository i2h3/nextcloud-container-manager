///
/// The request body sent to `POST /containers/create`.
///
struct CreateContainerRequest: Encodable {
    ///
    /// A single host-to-container port-binding entry.
    ///
    struct PortBinding: Encodable {
        /// The IP address on the host to bind to.
        let HostIp: String
        /// The port number on the host.
        let HostPort: String
    }

    ///
    /// Host-level configuration for the container.
    ///
    struct HostConfig: Encodable {
        /// When `true`, Docker removes the container automatically after it stops.
        let AutoRemove: Bool
        /// Maps container ports to host port bindings.
        let PortBindings: [String: [PortBinding]]
    }

    /// The image name and optional tag (e.g. `nextcloud:latest`).
    let Image: String
    /// Environment variables to inject into the container.
    let Env: [String]
    /// Ports that the container exposes.
    let ExposedPorts: [String: [String: String]]
    /// Host-level configuration such as port bindings and auto-removal.
    let HostConfig: HostConfig
}
