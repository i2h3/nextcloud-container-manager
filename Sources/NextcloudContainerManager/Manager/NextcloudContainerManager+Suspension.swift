// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Suspending and resuming a container for ``NextcloudContainerManager``.
///
/// These functions freeze every process inside a container and let them run again. They live in a dedicated file to keep simulating an outage separate from the core container lifecycle in ``NextcloudContainerManager``.
///
public extension NextcloudContainerManager {
    ///
    /// Suspends every process in the container with the given identifier.
    ///
    /// This is how a server that has gone away is simulated. Stopping the container is not the way to do it: containers deployed by this package remove themselves when they stop, so stopping one destroys the instance and everything in it. Suspending freezes it in place instead, which is what a connected client experiences as a server that stopped answering — connections stay open and nothing comes back — and ``resume(_:)`` brings it back with its state intact.
    ///
    /// - Parameters:
    ///     - id: The Docker container identifier or name returned by ``deploy(configuration:)``.
    ///
    /// - Throws: ``NextcloudContainerManagerError/dockerDesktopNotFound`` if Docker Desktop is not installed, ``NextcloudContainerManagerError/dockerDesktopLaunchFailed`` if it cannot be launched, or a `DockerClientError` for any API-level failure.
    ///
    static func pause(_ id: String) async throws {
        let client = try await makeDockerEngineClient()
        let response = try await client.post(path: "/containers/\(id)/pause")

        guard response.statusCode == 204 else {
            let message = String(data: response.body, encoding: .utf8) ?? "<no body>"
            throw DockerClientError.unexpectedStatusCode(response.statusCode, message)
        }
    }

    ///
    /// Lets every process in the container with the given identifier run again.
    ///
    /// The counterpart of ``pause(_:)``. A resumed container carries on from where it was frozen rather than starting over, so a client's view of the outage is that the server came back rather than that it was replaced.
    ///
    /// - Parameters:
    ///     - id: The Docker container identifier or name returned by ``deploy(configuration:)``.
    ///
    /// - Throws: ``NextcloudContainerManagerError/dockerDesktopNotFound`` if Docker Desktop is not installed, ``NextcloudContainerManagerError/dockerDesktopLaunchFailed`` if it cannot be launched, or a `DockerClientError` for any API-level failure.
    ///
    static func resume(_ id: String) async throws {
        let client = try await makeDockerEngineClient()
        let response = try await client.post(path: "/containers/\(id)/unpause")

        guard response.statusCode == 204 else {
            let message = String(data: response.body, encoding: .utf8) ?? "<no body>"
            throw DockerClientError.unexpectedStatusCode(response.statusCode, message)
        }
    }
}
