// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Verify that no container occupies a name yet, so that a deployment which requested it fails with a clear reason rather than with a Docker conflict error from container creation.
///
/// The name is looked up with `GET /containers/{name}/json`, which also finds stopped containers still holding the name. Because the lookup and the later creation are separate calls, the same small window remains as for ``ensurePortIsFree(_:)``, which is acceptable for the throwaway containers this package deploys.
///
/// - Parameters:
///     - name: The container name to verify. Expected to have passed ``validateContainerName(_:)`` already, so it is safe to embed in the request path.
///     - client: The Docker Engine client to use.
///
/// - Throws: ``NextcloudContainerManagerError/containerNameUnavailable(_:)`` when a container of that name exists, or another case of ``NextcloudContainerManagerError`` for a Docker Engine request that fails, times out or cannot be made.
///
func ensureContainerNameIsFree(_ name: String, using client: DockerEngineClient) async throws {
    let response = try await client.get(path: "/containers/\(name)/json")

    switch response.statusCode {
        case 404:
            return
        case 200:
            throw NextcloudContainerManagerError.containerNameUnavailable(name)
        default:
            try response.checked([200, 404])
    }
}
