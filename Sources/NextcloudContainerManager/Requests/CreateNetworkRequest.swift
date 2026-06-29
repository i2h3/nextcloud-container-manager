// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

///
/// The request body sent to `POST /networks/create`.
///
/// A user-defined bridge network is created per push-enabled deployment so the Nextcloud container and its Redis sidecar can resolve each other by name, which the default bridge network does not support.
///
struct CreateNetworkRequest: Encodable {
    ///
    /// The name to assign to the network, reused later to attach containers and to remove the network during teardown.
    ///
    let Name: String
}
