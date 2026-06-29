// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

///
/// The result of deploying a test container with ``NextcloudContainerManager/deploy(configuration:)``.
///
/// It carries the values needed to work with the running container: its ``id``, the host ``port`` the Nextcloud server is reachable on, and the ``configuration`` it was created with. All operations are performed through the stateless functions on ``NextcloudContainerManager`` keyed by ``id``, such as ``NextcloudContainerManager/addUser(_:inContainer:)`` or ``NextcloudContainerManager/delete(_:)``.
///
public struct NextcloudContainer: Identifiable, Sendable {
    ///
    /// The initial configuration this container was created with.
    ///
    public let configuration: NextcloudConfiguration

    ///
    /// The unique Docker container identifier.
    ///
    /// Pass this to the management functions on ``NextcloudContainerManager``, for example ``NextcloudContainerManager/addUser(_:inContainer:)`` or ``NextcloudContainerManager/delete(_:)``.
    ///
    public let id: String

    ///
    /// The host port mapped to the container's HTTP port 80.
    ///
    /// The Nextcloud server is reachable at `http://localhost:<port>`.
    ///
    public let port: UInt

    ///
    /// The host port the websocket push endpoint is reachable on, or `nil` when ``NextcloudConfiguration/pushNotifications`` was not enabled.
    ///
    /// When set, the High Performance Backend for Files is registered with the server at `http://localhost:<pushPort>` and clients discover it automatically through the Nextcloud capabilities API.
    ///
    public let pushPort: UInt?
}
