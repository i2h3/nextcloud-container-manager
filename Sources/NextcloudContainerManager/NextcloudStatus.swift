///
/// A subset of the JSON returned by the Nextcloud `status.php` endpoint.
///
struct NextcloudStatus: Decodable {
    /// Whether the Nextcloud instance has completed its initial installation.
    let installed: Bool
}
