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
    /// App identifiers to disable after the Nextcloud instance is ready.
    ///
    /// Each identifier is passed to ``NextcloudContainerManager/disableApp(_:inContainer:)`` during provisioning.
    ///
    public let disabledApps: [String]

    ///
    /// App identifiers to enable after the Nextcloud instance is ready, installing them first when they are not present yet.
    ///
    /// Each identifier is passed to ``NextcloudContainerManager/enableApp(_:inContainer:)`` during provisioning and, when the app is not installed yet, additionally to ``NextcloudContainerManager/addApp(_:inContainer:)``. Apps that are enabled by default and not listed in ``disabledApps`` are left as they are.
    ///
    public let enabledApps: [String]

    ///
    /// Identifiers of additional users to create after the Nextcloud instance is ready.
    ///
    /// Each identifier is passed to ``NextcloudContainerManager/addUser(_:inContainer:)`` during provisioning, which reuses the identifier as the account password.
    ///
    public let users: [String]

    ///
    /// Create a new configuration.
    ///
    /// - Parameters:
    ///     - tag: Always `latest` by default, if not specified differently.
    ///     - disabledApps: App identifiers to disable after deployment. Empty by default.
    ///     - enabledApps: App identifiers to enable, and install when necessary, after deployment. Empty by default.
    ///     - users: Identifiers of additional users to create after deployment. Empty by default.
    ///
    public init(tag: String = "latest", disabledApps: [String] = [], enabledApps: [String] = [], users: [String] = []) {
        self.tag = tag
        self.disabledApps = disabledApps
        self.enabledApps = enabledApps
        self.users = users
    }
}
