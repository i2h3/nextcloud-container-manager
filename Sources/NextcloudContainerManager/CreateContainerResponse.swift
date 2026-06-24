// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

///
/// The response body returned by `POST /containers/create`.
///
struct CreateContainerResponse: Decodable {
    /// The full container identifier assigned by Docker.
    let Id: String
}
