// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

///
/// A single progress message from the newline-delimited stream returned by `POST /images/create`.
///
/// Only the error field is decoded, because a pull failure is reported as a message carrying an `error` rather than as an HTTP status. The remaining progress fields are ignored.
///
struct ImagePullMessage: Decodable {
    ///
    /// The human-readable error description, present only on the message that reports a failed pull.
    ///
    let error: String?
}
