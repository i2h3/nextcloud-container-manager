// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

///
/// The request body sent to `POST /containers/{id}/exec`.
///
struct CreateExecRequest: Encodable {
    ///
    /// The command to run inside the container.
    ///
    let Cmd: [String]

    ///
    /// The user that the command is run as.
    ///
    let User: String

    ///
    /// The working directory for the command.
    ///
    let WorkingDir: String

    ///
    /// Environment variables in `VAR=value` form.
    ///
    /// Omitted from the request when `nil`.
    ///
    let Env: [String]?

    ///
    /// Whether the standard output of the command is connected to the stream that `POST /exec/{id}/start` answers with.
    ///
    /// Output exists only for the duration of that stream — the Docker Engine keeps none of it afterwards — so this has to be asked for before the command runs, and is left off for a command that is started detached and never read.
    ///
    let AttachStdout: Bool

    ///
    /// Whether the standard error of the command is connected to the stream that `POST /exec/{id}/start` answers with.
    ///
    /// Requested and omitted under the same conditions as ``AttachStdout``.
    ///
    let AttachStderr: Bool
}
