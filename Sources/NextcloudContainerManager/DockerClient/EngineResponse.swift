// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// What the Docker Engine answered a request with.
///
/// This carries the request path alongside the answer so that a failure can name what was asked for. The alternative — repeating the path at each place a status is checked — is the same literal written twice, and with no automated tests in this package a copy that drifts from its request would go unnoticed and mislabel every error it produced.
///
struct EngineResponse {
    ///
    /// The path the request was sent to, such as `/containers/abc123/json`.
    ///
    let path: String

    ///
    /// The HTTP status code the Docker Engine answered with.
    ///
    let statusCode: Int

    ///
    /// The response body, which is the Docker Engine's own explanation when the request failed.
    ///
    let body: Data

    ///
    /// The response body as text, for reporting.
    ///
    /// Bytes that are not valid UTF-8 are replaced rather than rejected, and an empty body is described rather than left blank, because this is diagnostic material and is more useful damaged than absent.
    ///
    var message: String {
        body.isEmpty ? "<no body>" : String(decoding: body, as: UTF8.self)
    }

    ///
    /// Returns the response when its status is one the caller expects, and throws otherwise.
    ///
    /// The accepted codes are given explicitly rather than defaulted, because the Docker Engine answers success with 200, 201 and 204 at different endpoints, and a few of them treat 304 or 404 as success too — a container that is already stopped, or a network that is already gone.
    ///
    /// - Parameters:
    ///     - acceptable: The status codes that count as success for this request.
    ///
    /// - Returns: The response itself, so that a check reads as part of the call that produced it.
    ///
    /// - Throws: ``NextcloudContainerManagerError/engineRequestFailed(path:statusCode:message:)`` when the status is not among `acceptable`.
    ///
    @discardableResult
    func checked(_ acceptable: Set<Int>) throws -> EngineResponse {
        guard acceptable.contains(statusCode) else {
            throw NextcloudContainerManagerError.engineRequestFailed(path: path, statusCode: statusCode, message: message)
        }

        return self
    }
}
