///
/// The request body sent to `POST /exec/{id}/start`.
///
struct StartExecRequest: Encodable {
    /// When `true`, the exec command runs in the background.
    let Detach: Bool
}
