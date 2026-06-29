// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

///
/// A subset of the response body returned by `GET /version`.
///
/// It is used to determine which architecture-specific `notify_push` binary to launch when ``NextcloudConfiguration/pushNotifications`` is enabled, because the app ships one binary per architecture under `bin/<arch>/`.
///
struct DockerVersionResponse: Decodable {
    ///
    /// The hardware architecture the Docker Engine runs on, in Go's naming (for example `arm64` or `amd64`).
    ///
    let Arch: String
}
