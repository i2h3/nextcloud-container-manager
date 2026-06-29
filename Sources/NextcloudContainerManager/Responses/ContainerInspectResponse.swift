// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

///
/// A subset of the response body returned by `GET /containers/{id}/json`.
///
/// ``NextcloudContainerManager/delete(_:)`` inspects a container before removing it to read the deployment label written during ``NextcloudContainerManager/deploy(configuration:)``, which tells it whether a Redis sidecar and a user-defined network must be torn down alongside the Nextcloud container.
///
struct ContainerInspectResponse: Decodable {
    ///
    /// The container's configuration as reported by the Docker Engine.
    ///
    struct Config: Decodable {
        ///
        /// The user-defined labels attached to the container at creation time, or `nil` when none were set.
        ///
        let Labels: [String: String]?
    }

    ///
    /// The configuration the container was created with.
    ///
    let Config: Config
}
