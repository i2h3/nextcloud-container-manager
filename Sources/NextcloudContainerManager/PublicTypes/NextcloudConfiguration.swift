// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

///
/// A configuration to set up a Nextcloud container with.
///
public struct NextcloudConfiguration: Sendable {
    ///
    /// The Docker container tag.
    ///
    public let tag: String

    ///
    /// The name to give the Docker container, or `nil` to let the Docker Engine generate one.
    ///
    /// A generated name is right for a throwaway container, but wrong whenever the container has to be recognized from outside this process: a name pinned here appears in `docker ps` as given and doubles as the identifier every function on ``NextcloudContainerManager`` accepts in place of ``NextcloudContainer/id``, so a leftover deployment can be reclaimed without having persisted its identifier. It is the counterpart of ``port`` for the same reason — stability across runs.
    ///
    /// Deployment fails with ``NextcloudContainerManagerError/invalidContainerName(_:)`` when the name is not one the Docker Engine accepts, and with ``NextcloudContainerManagerError/containerNameUnavailable(_:)`` when another container, running or stopped, holds it already.
    ///
    public let name: String?

    ///
    /// App identifiers to disable after the Nextcloud instance is ready.
    ///
    /// Each identifier is passed to ``NextcloudContainerManager/disableApp(_:timeout:inContainer:)`` during provisioning.
    ///
    public let disabledApps: [String]

    ///
    /// App identifiers to enable after the Nextcloud instance is ready, installing them first when they are not present yet.
    ///
    /// Each identifier is passed to ``NextcloudContainerManager/enableApp(_:timeout:inContainer:)`` during provisioning and, when the app is not installed yet, additionally to ``NextcloudContainerManager/addApp(_:timeout:inContainer:)``. Apps that are enabled by default and not listed in ``disabledApps`` are left as they are.
    ///
    /// Provisioning uses the default allowances of both functions, so an app the image does not ship already is downloaded from the app store under ``NextcloudContainerManager/defaultAppInstallationTimeout``. That is deliberately not tunable here, because a per-deployment number would have to be guessed before it is known which of the listed apps are missing and how large they are. A caller who needs a different allowance for a particular app leaves it out of this list and calls ``NextcloudContainerManager/addApp(_:timeout:inContainer:)`` with an explicit `timeout`, or with `nil` to wait for as long as the download takes, once ``NextcloudContainerManager/deploy(configuration:)`` has returned.
    ///
    public let enabledApps: [String]

    ///
    /// Identifiers of additional users to create after the Nextcloud instance is ready.
    ///
    /// Each identifier is passed to ``NextcloudContainerManager/addUser(_:timeout:inContainer:)`` during provisioning, which reuses the identifier as the account password.
    ///
    public let users: [String]

    ///
    /// The host port to publish the Nextcloud server on, or `nil` to let the kernel pick a free one.
    ///
    /// A deployment normally takes whatever port happens to be free, which is right for a throwaway container. It is wrong whenever something outside the container remembers the address: a macOS File Provider domain, for instance, is named after the server it belongs to, and a name which changes on every deployment is a new domain each time — with its own privacy consent to be granted by hand. Pinning the port keeps such names stable across runs.
    ///
    /// Deployment fails with ``NextcloudContainerManagerError/portUnavailable(_:)`` when the requested port is already taken.
    ///
    public let port: UInt16?

    ///
    /// The host port to publish the websocket push endpoint on, or `nil` to let the kernel pick a free one.
    ///
    /// Only meaningful together with ``pushNotifications``, and pinned for the same reasons as ``port``.
    ///
    public let pushPort: UInt16?

    ///
    /// Whether to enable the High Performance Backend for Files so connected clients receive websocket push notifications instead of polling.
    ///
    /// When `true`, ``NextcloudContainerManager/deploy(configuration:)`` additionally deploys a Redis sidecar on a dedicated network, configures the Nextcloud instance to use it, installs the `notify_push` app, launches its push daemon inside the container and registers it with the server. The host port the push endpoint is reachable on is reported as ``NextcloudContainer/pushPort``. Tearing the deployment down with ``NextcloudContainerManager/delete(_:)`` removes the sidecar and network as well. Disabled by default.
    ///
    public let pushNotifications: Bool

    ///
    /// Create a new configuration.
    ///
    /// - Parameters:
    ///     - tag: Always `latest` by default, if not specified differently.
    ///     - disabledApps: App identifiers to disable after deployment. Empty by default.
    ///     - enabledApps: App identifiers to enable, and install when necessary, after deployment. Empty by default.
    ///     - users: Identifiers of additional users to create after deployment. Empty by default.
    ///     - pushNotifications: Whether to enable the High Performance Backend for Files. Disabled by default.
    ///     - name: The name to give the Docker container. Generated by the Docker Engine by default.
    ///     - port: The host port to publish the Nextcloud server on. A free one is picked by default.
    ///     - pushPort: The host port to publish the websocket push endpoint on. A free one is picked by default.
    ///
    public init(tag: String = "latest", disabledApps: [String] = [], enabledApps: [String] = [], users: [String] = [], pushNotifications: Bool = false, name: String? = nil, port: UInt16? = nil, pushPort: UInt16? = nil) {
        self.tag = tag
        self.disabledApps = disabledApps
        self.enabledApps = enabledApps
        self.name = name
        self.port = port
        self.pushNotifications = pushNotifications
        self.pushPort = pushPort
        self.users = users
    }
}
