// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The primary interface of this library.
///
public enum NextcloudContainerManager {
    static func makeDockerEngineClient() async throws -> DockerEngineClient {
        let client: DockerEngineClient

        do {
            client = try DockerEngineClient()
        } catch let DockerClientError.socketNotFound(socketPath) {
            guard FileManager.default.fileExists(atPath: "/Applications/Docker.app") else {
                throw NextcloudContainerManagerError.dockerDesktopNotFound
            }

            let launcher = Process()
            launcher.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            launcher.arguments = ["-a", "Docker"]

            do {
                try launcher.run()
                launcher.waitUntilExit()
            } catch {
                throw NextcloudContainerManagerError.dockerDesktopLaunchFailed
            }

            guard launcher.terminationStatus == 0 else {
                throw NextcloudContainerManagerError.dockerDesktopLaunchFailed
            }

            let deadline = Date.now.addingTimeInterval(10)

            while !FileManager.default.fileExists(atPath: socketPath), Date.now < deadline {
                try await Task.sleep(for: .milliseconds(500))
            }

            client = try DockerEngineClient()
        }

        return client
    }

    ///
    /// Deploy a new container.
    ///
    /// If the Docker Engine socket is not found, this method checks for Docker Desktop at `/Applications/Docker.app` and attempts to launch it, polling for the socket to become available for up to 10 seconds before retrying. If Docker Desktop is not installed or cannot be launched, a ``NextcloudContainerManagerError`` is thrown.
    ///
    /// When ``NextcloudConfiguration/pushNotifications`` is enabled, a Redis sidecar is deployed on a dedicated network and the High Performance Backend for Files is provisioned, exposing the push endpoint on ``NextcloudContainer/pushPort``. The supporting infrastructure is removed again automatically if any step fails.
    ///
    /// - Parameters:
    ///     - configuration: Deployment options. Defaults to ``NextcloudConfiguration/init(tag:disabledApps:enabledApps:users:pushNotifications:)``.
    ///
    /// - Returns: A handle for the running container.
    ///
    /// - Throws: ``NextcloudContainerManagerError/dockerDesktopNotFound`` if Docker Desktop is not installed, ``NextcloudContainerManagerError/dockerDesktopLaunchFailed`` if it cannot be launched, ``NextcloudContainerManagerError/unsupportedArchitecture(_:)`` if the push daemon cannot run on the Docker Engine's architecture, or a `DockerClientError` for any API-level failure.
    ///
    public static func deploy(configuration: NextcloudConfiguration = NextcloudConfiguration()) async throws -> NextcloudContainer {
        let client = try await makeDockerEngineClient()

        // 1. Find a free host port to forward to container port 80.
        let port = try findFreePort()

        // 2. When push notifications are enabled, find a second free port for the push endpoint and assemble a deployment identifier used to name and later reclaim the supporting infrastructure.
        let deployment: String? = configuration.pushNotifications ? UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() : nil
        let pushPort: UInt16? = configuration.pushNotifications ? try findFreePort() : nil

        // 3. Assemble the create-container options, extending them for the High Performance Backend when requested.
        var environment = [
            "SQLITE_DATABASE=nextcloud.sqlite",
            "NEXTCLOUD_ADMIN_USER=admin",
            "NEXTCLOUD_ADMIN_PASSWORD=admin",
        ]

        var exposedPorts: [String: [String: String]] = ["80/tcp": [:]]

        var portBindings: [String: [CreateContainerRequest.PortBinding]] = [
            "80/tcp": [.init(HostIp: "0.0.0.0", HostPort: "\(port)")],
        ]

        var networkMode: String?

        var labels: [String: String]?

        if let deployment, let pushPort {
            let network = networkName(for: deployment)

            // The create endpoint never pulls images, so the Redis image is pulled explicitly before the sidecar is created on its own network.
            try await pullImage(redisImage, using: client)
            try await createNetwork(named: network, using: client)

            do {
                try await deployRedisSidecar(deployment: deployment, network: network, using: client)
            } catch {
                try? await removeNetwork(named: network, using: client)

                throw error
            }

            // Setting REDIS_HOST makes the Nextcloud image configure the distributed cache the push daemon relies on.
            environment.append("REDIS_HOST=\(redisAlias)")
            exposedPorts["\(pushPort)/tcp"] = [:]
            portBindings["\(pushPort)/tcp"] = [.init(HostIp: "0.0.0.0", HostPort: "\(pushPort)")]
            networkMode = network
            labels = [deploymentLabelKey: deployment]
        }

        let requestBody = CreateContainerRequest(
            Image: "nextcloud:\(configuration.tag)",
            Env: environment,
            ExposedPorts: exposedPorts,
            HostConfig: .init(AutoRemove: true, PortBindings: portBindings, NetworkMode: networkMode),
            Labels: labels,
            NetworkingConfig: nil
        )

        // 4. Create and start the container, then provision it, rolling back the container and any supporting infrastructure if a later step fails so nothing is leaked.
        var createdId: String?

        do {
            let createResponse = try await client.post(path: "/containers/create", body: requestBody)

            guard createResponse.statusCode == 201 else {
                let message = String(data: createResponse.body, encoding: .utf8) ?? "<no body>"
                throw DockerClientError.unexpectedStatusCode(createResponse.statusCode, message)
            }

            let created = try JSONDecoder().decode(CreateContainerResponse.self, from: createResponse.body)
            createdId = created.Id

            let startResponse = try await client.post(path: "/containers/\(created.Id)/start")

            guard startResponse.statusCode == 204 else {
                let message = String(data: startResponse.body, encoding: .utf8) ?? "<no body>"
                throw DockerClientError.unexpectedStatusCode(startResponse.statusCode, message)
            }

            let container = NextcloudContainer(
                configuration: configuration,
                id: created.Id,
                port: UInt(port),
                pushPort: pushPort.map(UInt.init)
            )

            try await provision(container)

            return container
        } catch {
            if let createdId {
                try? await forceRemoveContainer(createdId, using: client)
            }

            if let deployment {
                try? await tearDownPushInfrastructure(deployment: deployment, using: client)
            }

            throw error
        }
    }

    ///
    /// Stops a Nextcloud server container by its identifier and deletes all of its data.
    ///
    /// Because the container was created with `AutoRemove`, stopping it is sufficient — Docker removes it automatically once it exits. The call is idempotent: containers that are already stopped or have already been removed do not cause an error.
    ///
    /// When the container belongs to a push-enabled deployment, its Redis sidecar and network are removed as well, identified by the deployment label written during ``deploy(configuration:)``.
    ///
    /// - Parameters:
    ///     - id: The Docker container identifier returned by ``deploy(configuration:)``.
    ///
    /// - Throws: ``NextcloudContainerManagerError/dockerDesktopNotFound`` if Docker Desktop is not installed, ``NextcloudContainerManagerError/dockerDesktopLaunchFailed`` if it cannot be launched, or a `DockerClientError` for any API-level failure.
    ///
    public static func delete(_ id: String) async throws {
        let client = try await makeDockerEngineClient()

        // A push-enabled deployment is removed as a whole: its container is force-removed so the network has no remaining endpoints, then the Redis sidecar and network are torn down too.
        if let deployment = try? await deploymentIdentifier(of: id, using: client) {
            try? await forceRemoveContainer(redisContainerName(for: deployment), using: client)
            try await forceRemoveContainer(id, using: client)
            try await removeNetwork(named: networkName(for: deployment), using: client)

            return
        }

        // Acceptable status codes:
        //   204 – successfully stopped
        //   304 – container was already stopped (already auto-removed)
        //   404 – container no longer exists (already removed)
        let response = try await client.post(path: "/containers/\(id)/stop")

        guard [204, 304, 404].contains(response.statusCode) else {
            let message = String(data: response.body, encoding: .utf8) ?? "<no body>"
            throw DockerClientError.unexpectedStatusCode(response.statusCode, message)
        }
    }
}
