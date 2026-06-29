// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

///
/// A subset of the response body returned by `GET /exec/{id}/json`.
///
struct ExecInspectResponse: Decodable {
    ///
    /// Whether the exec instance is still running.
    ///
    let Running: Bool

    ///
    /// The exit code of the command, or `nil` while it is still running.
    ///
    let ExitCode: Int?
}
