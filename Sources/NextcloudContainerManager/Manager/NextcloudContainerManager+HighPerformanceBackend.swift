// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// High Performance Backend for Files support for ``NextcloudContainerManager``.
///
/// These members provision and tear down the Redis sidecar, the dedicated network and the `notify_push` daemon that back ``NextcloudConfiguration/pushNotifications``. They live in a dedicated file to keep the push-notification concern separate from the core container lifecycle in ``NextcloudContainerManager``.
///
extension NextcloudContainerManager {
    ///
    /// The label key under which the per-deployment identifier is stored on the Nextcloud container so ``delete(_:)`` can find and remove the matching Redis sidecar and network.
    ///
    static let deploymentLabelKey = "io.github.i2h3.nextcloud-container-manager.deployment"

    ///
    /// The image used for the Redis sidecar that backs the High Performance Backend.
    ///
    static let redisImage = "redis:7-alpine"

    ///
    /// The network alias the Redis sidecar is reachable under, matching the `REDIS_HOST` value passed to the Nextcloud container.
    ///
    static let redisAlias = "redis"

    ///
    /// Derives the deterministic name of the user-defined network for a deployment from its identifier.
    ///
    /// - Parameters:
    ///     - deployment: The deployment identifier assigned in ``deploy(configuration:)``.
    ///
    /// - Returns: The network name.
    ///
    static func networkName(for deployment: String) -> String {
        "ncm-net-\(deployment)"
    }

    ///
    /// Derives the deterministic name of the Redis sidecar container for a deployment from its identifier.
    ///
    /// - Parameters:
    ///     - deployment: The deployment identifier assigned in ``deploy(configuration:)``.
    ///
    /// - Returns: The container name.
    ///
    static func redisContainerName(for deployment: String) -> String {
        "ncm-redis-\(deployment)"
    }

    ///
    /// Sets up the High Performance Backend for Files in an already provisioned container.
    ///
    /// This trusts the loopback address so the push daemon's callback passes the trusted-proxy self-test, installs the `notify_push` app, launches its bundled daemon inside the container, waits for it to start listening, and finally registers the push endpoint. Registration runs the app's self-test and only succeeds when every check passes, so a failure here surfaces as a thrown error.
    ///
    /// - Parameters:
    ///     - container: The running, provisioned container to set the backend up in.
    ///
    static func setUpPushNotifications(_ container: NextcloudContainer) async throws {
        guard let pushPort = container.pushPort else {
            return
        }

        // 1. Trust the loopback address the daemon calls back from so the trusted-proxy self-test check passes.
        try await runOCC(["config:system:set", "trusted_proxies", "0", "--value=127.0.0.1"], inContainer: container.id)

        // 2. Install and enable the notify_push app, which also ships the push daemon binary.
        try await addApp("notify_push", inContainer: container.id)

        // 3. Launch the push daemon inside the container without waiting for it to exit, pointing it at the Nextcloud config and the in-container Nextcloud URL.
        let binaryPath = try await notifyPushBinaryPath()
        try await runExec([binaryPath, "/var/www/html/config/config.php", "--port", "\(pushPort)"], environment: ["NEXTCLOUD_URL=http://localhost"], waitsForExit: false, inContainer: container.id)

        // 4. Wait for the daemon to start listening before registering it.
        try await waitUntilPushReady(port: pushPort)

        // 5. Register the push endpoint, which runs the app's self-test and only succeeds when every check passes.
        try await runOCC(["notify_push:setup", "http://localhost:\(pushPort)"], inContainer: container.id)
    }

    ///
    /// Resolves the in-container path of the architecture-specific `notify_push` daemon binary.
    ///
    /// The app ships one binary per architecture under `bin/<arch>/`, so the Docker Engine's architecture reported by `GET /version` is mapped to the matching subdirectory.
    ///
    /// - Returns: The absolute path of the daemon binary inside the container.
    ///
    /// - Throws: ``NextcloudContainerManagerError/unsupportedArchitecture(_:)`` when the reported architecture has no bundled binary.
    ///
    private static func notifyPushBinaryPath() async throws -> String {
        let client = try await makeDockerEngineClient()
        let response = try await client.get(path: "/version")
        let version = try JSONDecoder().decode(DockerVersionResponse.self, from: response.body)

        let architecture: String

        switch version.Arch {
            case "amd64":
                architecture = "x86_64"
            case "arm64":
                architecture = "aarch64"
            case "arm":
                architecture = "armv7"
            default:
                throw NextcloudContainerManagerError.unsupportedArchitecture(version.Arch)
        }

        return "/var/www/html/custom_apps/notify_push/bin/\(architecture)/notify_push"
    }

    ///
    /// Polls the push endpoint on the given host port until the daemon answers, or a timeout is reached.
    ///
    /// Any HTTP response, including an error status, proves the daemon is listening, so registration can proceed.
    ///
    /// - Parameters:
    ///     - port: The host port the push daemon is published on.
    ///
    /// - Throws: ``DockerClientError/timeout`` when the daemon does not start listening within 30 seconds.
    ///
    private static func waitUntilPushReady(port: UInt) async throws {
        let url = URL(string: "http://localhost:\(port)/")!
        let deadline = Date().addingTimeInterval(30)

        while Date() < deadline {
            do {
                let (_, response) = try await URLSession.shared.data(from: url)

                if response is HTTPURLResponse {
                    return
                }
            } catch {
                // The daemon is not listening yet – retry after a short delay.
            }

            try await Task.sleep(nanoseconds: 250_000_000)
        }

        throw DockerClientError.timeout
    }

    ///
    /// Pulls an image so it is available locally, because `POST /containers/create` never pulls missing images itself.
    ///
    /// The Docker Engine streams progress and closes the connection when the pull finishes. A pull error is reported inside that stream rather than as an HTTP status, so it surfaces later as a missing-image failure from container creation.
    ///
    /// - Parameters:
    ///     - image: The image reference, optionally including a tag (e.g. `redis:7-alpine`).
    ///     - client: The Docker Engine client to use.
    ///
    static func pullImage(_ image: String, using client: DockerEngineClient) async throws {
        let components = image.split(separator: ":", maxSplits: 1)
        let name = String(components[0])
        let tag = components.count > 1 ? String(components[1]) : "latest"

        let response = try await client.post(path: "/images/create?fromImage=\(name)&tag=\(tag)")

        guard response.statusCode == 200 else {
            let message = String(data: response.body, encoding: .utf8) ?? "<no body>"
            throw DockerClientError.unexpectedStatusCode(response.statusCode, message)
        }
    }

    ///
    /// Creates a user-defined bridge network with the given name.
    ///
    /// - Parameters:
    ///     - name: The network name.
    ///     - client: The Docker Engine client to use.
    ///
    static func createNetwork(named name: String, using client: DockerEngineClient) async throws {
        let response = try await client.post(path: "/networks/create", body: CreateNetworkRequest(Name: name))

        guard response.statusCode == 201 else {
            let message = String(data: response.body, encoding: .utf8) ?? "<no body>"
            throw DockerClientError.unexpectedStatusCode(response.statusCode, message)
        }
    }

    ///
    /// Creates and starts the Redis sidecar for a deployment on the given network.
    ///
    /// The sidecar joins the network under the ``redisAlias`` alias so the Nextcloud container and the push daemon can reach it by name. It is created with `AutoRemove` and labelled with the deployment identifier so it is cleaned up alongside the Nextcloud container.
    ///
    /// - Parameters:
    ///     - deployment: The deployment identifier the sidecar belongs to.
    ///     - network: The name of the network to attach the sidecar to.
    ///     - client: The Docker Engine client to use.
    ///
    static func deployRedisSidecar(deployment: String, network: String, using client: DockerEngineClient) async throws {
        let name = redisContainerName(for: deployment)

        let requestBody = CreateContainerRequest(
            Image: redisImage,
            Env: nil,
            ExposedPorts: nil,
            HostConfig: .init(AutoRemove: true, PortBindings: nil, NetworkMode: network),
            Labels: [deploymentLabelKey: deployment],
            NetworkingConfig: .init(EndpointsConfig: [network: .init(Aliases: [redisAlias])])
        )

        let createResponse = try await client.post(path: "/containers/create?name=\(name)", body: requestBody)

        guard createResponse.statusCode == 201 else {
            let message = String(data: createResponse.body, encoding: .utf8) ?? "<no body>"
            throw DockerClientError.unexpectedStatusCode(createResponse.statusCode, message)
        }

        let startResponse = try await client.post(path: "/containers/\(name)/start")

        guard startResponse.statusCode == 204 else {
            let message = String(data: startResponse.body, encoding: .utf8) ?? "<no body>"
            throw DockerClientError.unexpectedStatusCode(startResponse.statusCode, message)
        }
    }

    ///
    /// Force-removes a container by identifier or name, tolerating one that no longer exists.
    ///
    /// Removing synchronously (rather than relying on `AutoRemove`) detaches the container from its network immediately, which lets the network be removed right afterwards.
    ///
    /// - Parameters:
    ///     - idOrName: The container identifier or name.
    ///     - client: The Docker Engine client to use.
    ///
    static func forceRemoveContainer(_ idOrName: String, using client: DockerEngineClient) async throws {
        let response = try await client.delete(path: "/containers/\(idOrName)?force=true&v=true")

        guard [200, 204, 404].contains(response.statusCode) else {
            let message = String(data: response.body, encoding: .utf8) ?? "<no body>"
            throw DockerClientError.unexpectedStatusCode(response.statusCode, message)
        }
    }

    ///
    /// Removes a network by name, tolerating one that no longer exists and retrying briefly while it still reports active endpoints.
    ///
    /// - Parameters:
    ///     - name: The network name.
    ///     - client: The Docker Engine client to use.
    ///
    static func removeNetwork(named name: String, using client: DockerEngineClient) async throws {
        let deadline = Date().addingTimeInterval(10)

        while true {
            let response = try await client.delete(path: "/networks/\(name)")

            if [204, 404].contains(response.statusCode) {
                return
            }

            // A network that still has attached endpoints answers 403; retry briefly while containers finish detaching.
            if response.statusCode == 403, Date() < deadline {
                try await Task.sleep(nanoseconds: 250_000_000)

                continue
            }

            let message = String(data: response.body, encoding: .utf8) ?? "<no body>"
            throw DockerClientError.unexpectedStatusCode(response.statusCode, message)
        }
    }

    ///
    /// Removes the supporting infrastructure of a push-enabled deployment, namely its Redis sidecar and network.
    ///
    /// - Parameters:
    ///     - deployment: The deployment identifier whose infrastructure should be torn down.
    ///     - client: The Docker Engine client to use.
    ///
    static func tearDownPushInfrastructure(deployment: String, using client: DockerEngineClient) async throws {
        try? await forceRemoveContainer(redisContainerName(for: deployment), using: client)
        try await removeNetwork(named: networkName(for: deployment), using: client)
    }

    ///
    /// Reads the deployment identifier label from a container, or returns `nil` when the container is not part of a push-enabled deployment or no longer exists.
    ///
    /// - Parameters:
    ///     - id: The container identifier to inspect.
    ///     - client: The Docker Engine client to use.
    ///
    /// - Returns: The deployment identifier, or `nil`.
    ///
    static func deploymentIdentifier(of id: String, using client: DockerEngineClient) async throws -> String? {
        let response = try await client.get(path: "/containers/\(id)/json")

        guard response.statusCode == 200 else {
            return nil
        }

        let inspect = try JSONDecoder().decode(ContainerInspectResponse.self, from: response.body)

        return inspect.Config.Labels?[deploymentLabelKey]
    }
}
