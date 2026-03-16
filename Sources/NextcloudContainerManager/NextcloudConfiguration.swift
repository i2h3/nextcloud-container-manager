///
/// A configuration to set up a Nextcloud container with.
///
public struct NextcloudConfiguration: Sendable {
    ///
    /// The Docker container tag.
    ///
    public let tag: String

    ///
    /// Create a new configuration.
    ///
    /// - Parameters:
    ///     - tag: Always `latest` by default, if not specified differently.
    ///
    public init(tag: String = "latest") {
        self.tag = tag
    }
}
