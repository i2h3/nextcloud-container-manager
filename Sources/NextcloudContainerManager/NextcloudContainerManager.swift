import Foundation

///
/// The primary interface of this library.
///
public enum NextcloudContainerManager {
    ///
    /// Deploy a new container.
    ///
    /// If the Docker Engine socket is not found, this method checks for Docker Desktop at
    /// `/Applications/Docker.app` and attempts to launch it. It then polls for the socket
    /// to become available for up to 10 seconds before retrying. If Docker Desktop is not
    /// installed or cannot be launched, a ``NextcloudContainerManagerError`` is thrown.
    ///
    /// - Parameters:
    ///     - configuration: Deployment options. Defaults to ``NextcloudConfiguration/init()``.
    ///
    /// - Returns: A handle for the running container.
    ///
    /// - Throws: ``NextcloudContainerManagerError/dockerDesktopNotFound`` if Docker Desktop
    ///     is not installed, ``NextcloudContainerManagerError/dockerDesktopLaunchFailed`` if
    ///     it cannot be launched, or a ``DockerClientError`` for any API-level failure.
    ///
    public static func deploy(configuration: NextcloudConfiguration = NextcloudConfiguration()) async throws -> NextcloudContainer {
        let client: DockerEngineClient
        do {
            client = try DockerEngineClient()
        } catch DockerClientError.socketNotFound(let socketPath) {
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

        // 1. Find a free host port to forward to container port 80.
        let port = try findFreePort()

        // 2. Build the create-container request body.
        let requestBody = CreateContainerRequest(
            Image: "nextcloud:\(configuration.tag)",
            Env: [
                "SQLITE_DATABASE=nextcloud.sqlite",
                "NEXTCLOUD_ADMIN_USER=admin",
                "NEXTCLOUD_ADMIN_PASSWORD=admin",
            ],
            ExposedPorts: ["80/tcp": [:]],
            HostConfig: .init(
                AutoRemove: true,
                PortBindings: [
                    "80/tcp": [
                        .init(HostIp: "0.0.0.0", HostPort: "\(port)"),
                    ],
                ]
            )
        )

        // 3. Create the container.
        let createResponse = try await client.post(path: "/containers/create", body: requestBody)
        guard createResponse.statusCode == 201 else {
            let message = String(data: createResponse.body, encoding: .utf8) ?? "<no body>"
            throw DockerClientError.unexpectedStatusCode(createResponse.statusCode, message)
        }
        let created = try JSONDecoder().decode(CreateContainerResponse.self, from: createResponse.body)

        // 4. Start the container.
        let startResponse = try await client.post(path: "/containers/\(created.Id)/start")
        guard startResponse.statusCode == 204 else {
            let message = String(data: startResponse.body, encoding: .utf8) ?? "<no body>"
            throw DockerClientError.unexpectedStatusCode(startResponse.statusCode, message)
        }

        let container = NextcloudContainer(
            configuration: configuration,
            id: created.Id,
            port: UInt(port),
            client: client
        )

        // 5. Run post-deployment provisioning (wait for readiness, disable apps).
        try await container.provision()

        return container
    }
}
