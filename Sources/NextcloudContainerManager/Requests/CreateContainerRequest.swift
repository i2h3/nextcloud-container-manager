// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

///
/// The request body sent to `POST /containers/create`.
///
struct CreateContainerRequest: Encodable {
    ///
    /// A single host-to-container port-binding entry.
    ///
    struct PortBinding: Encodable {
        ///
        /// The IP address on the host to bind to.
        ///
        let HostIp: String

        ///
        /// The port number on the host.
        ///
        let HostPort: String
    }

    ///
    /// Host-level configuration for the container.
    ///
    struct HostConfig: Encodable {
        ///
        /// When `true`, Docker removes the container automatically after it stops.
        ///
        let AutoRemove: Bool

        ///
        /// Maps container ports to host port bindings.
        ///
        /// Omitted from the request when `nil`, for example for the Redis sidecar which publishes no ports.
        ///
        let PortBindings: [String: [PortBinding]]?

        ///
        /// The name of the network to attach the container to, or `nil` to use Docker's default bridge network.
        ///
        /// Push-enabled deployments set this to the per-deployment user-defined network so containers resolve each other by name.
        ///
        let NetworkMode: String?
    }

    ///
    /// The settings applied to a container's endpoint on a specific network.
    ///
    struct EndpointSettings: Encodable {
        ///
        /// Additional DNS names the container is reachable under on the network, for example `redis` for the Redis sidecar.
        ///
        /// Omitted from the request when `nil`.
        ///
        let Aliases: [String]?
    }

    ///
    /// The networking configuration applied to the container at creation time.
    ///
    /// Unlike ``HostConfig/NetworkMode``, this carries per-network endpoint settings such as ``EndpointSettings/Aliases``.
    ///
    struct NetworkingConfig: Encodable {
        ///
        /// The endpoint settings keyed by network name.
        ///
        let EndpointsConfig: [String: EndpointSettings]
    }

    ///
    /// The image name and optional tag (e.g. `nextcloud:latest`).
    ///
    let Image: String

    ///
    /// Environment variables to inject into the container.
    ///
    /// Omitted from the request when `nil`.
    ///
    let Env: [String]?

    ///
    /// Ports that the container exposes.
    ///
    /// Omitted from the request when `nil`.
    ///
    let ExposedPorts: [String: [String: String]]?

    ///
    /// Host-level configuration such as port bindings, network attachment and auto-removal.
    ///
    let HostConfig: HostConfig

    ///
    /// User-defined labels to attach to the container.
    ///
    /// Used to mark the Nextcloud container as part of a push-enabled deployment so ``NextcloudContainerManager/delete(_:)`` can tear down its Redis sidecar and network. Omitted from the request when `nil`.
    ///
    let Labels: [String: String]?

    ///
    /// Per-network endpoint settings, used to give the Redis sidecar its `redis` alias.
    ///
    /// Omitted from the request when `nil`.
    ///
    let NetworkingConfig: NetworkingConfig?
}
