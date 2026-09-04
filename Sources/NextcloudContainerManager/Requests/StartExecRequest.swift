// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

///
/// The request body sent to `POST /exec/{id}/start`.
///
struct StartExecRequest: Encodable {
    ///
    /// When `true`, the exec command runs in the background.
    ///
    /// When `false`, the Docker Engine answers with the command's output instead and holds the connection open until the command exits, which is how a command is both waited for and read.
    ///
    let Detach: Bool

    ///
    /// Whether the command is given a pseudo-terminal.
    ///
    /// Always `false`, because a pseudo-terminal merges the two output streams into one and drops the framing that ``demultiplexDockerStream(_:)`` relies on to tell them apart.
    ///
    let Tty: Bool
}
