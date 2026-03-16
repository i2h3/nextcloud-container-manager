///
/// A subset of the response body returned by `GET /exec/{id}/json`.
///
struct ExecInspectResponse: Decodable {
    /// Whether the exec instance is still running.
    let Running: Bool
    /// The exit code of the command. Only meaningful when `Running` is `false`.
    let ExitCode: Int
}
