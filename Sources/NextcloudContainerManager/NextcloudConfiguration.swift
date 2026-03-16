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
    public let disabledApps: [String]

    ///
    /// Create a new configuration.
    ///
    /// - Parameters:
    ///     - tag: Always `latest` by default, if not specified differently.
    ///     - disabledApps: App identifiers to disable after deployment. Empty by default.
    ///
    public init(tag: String = "latest", disabledApps: [String] = []) {
        self.tag = tag
        self.disabledApps = disabledApps
    }
}
