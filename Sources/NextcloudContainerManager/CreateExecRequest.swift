///
/// The request body sent to `POST /containers/{id}/exec`.
///
struct CreateExecRequest: Encodable {
    /// The command to run inside the container.
    let Cmd: [String]
    /// The user that the command is run as.
    let User: String
    /// The working directory for the command.
    let WorkingDir: String
}
