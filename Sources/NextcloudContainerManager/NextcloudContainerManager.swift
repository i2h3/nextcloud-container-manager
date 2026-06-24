// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The primary interface of this library.
///
public enum NextcloudContainerManager {
    private static func makeDockerEngineClient() async throws -> DockerEngineClient {
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
    /// If the Docker Engine socket is not found, this method checks for Docker Desktop at
    /// `/Applications/Docker.app` and attempts to launch it. It then polls for the socket
    /// to become available for up to 10 seconds before retrying. If Docker Desktop is not
    /// installed or cannot be launched, a ``NextcloudContainerManagerError`` is thrown.
    ///
    /// - Parameters:
    ///     - configuration: Deployment options. Defaults to ``NextcloudConfiguration/init(tag:disabledApps:enabledApps:users:)``.
    ///
    /// - Returns: A handle for the running container.
    ///
    /// - Throws: ``NextcloudContainerManagerError/dockerDesktopNotFound`` if Docker Desktop
    ///     is not installed, ``NextcloudContainerManagerError/dockerDesktopLaunchFailed`` if
    ///     it cannot be launched, or a `DockerClientError` for any API-level failure.
    ///
    public static func deploy(configuration: NextcloudConfiguration = NextcloudConfiguration()) async throws -> NextcloudContainer {
        let client = try await makeDockerEngineClient()

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
            port: UInt(port)
        )

        // 5. Run post-deployment provisioning, tearing the container down again when it fails so a half-provisioned instance is not leaked.
        do {
            try await provision(container)
        } catch {
            try? await delete(container.id)

            throw error
        }

        return container
    }

    ///
    /// Stops a Nextcloud server container by its identifier and deletes all of its data.
    ///
    /// Because the container was created with `AutoRemove`, stopping it is sufficient —
    /// Docker removes it automatically once it exits. The call is idempotent: containers
    /// that are already stopped or have already been removed do not cause an error.
    ///
    /// - Parameters:
    ///     - id: The Docker container identifier returned by ``deploy(configuration:)``.
    ///
    /// - Throws: ``NextcloudContainerManagerError/dockerDesktopNotFound`` if Docker Desktop
    ///     is not installed, ``NextcloudContainerManagerError/dockerDesktopLaunchFailed`` if
    ///     it cannot be launched, or a `DockerClientError` for any API-level failure.
    ///
    public static func delete(_ id: String) async throws {
        let client = try await makeDockerEngineClient()

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

    // MARK: - App management

    ///
    /// Installs a Nextcloud app by executing `occ app:install` in the container with the given identifier.
    ///
    /// - Parameters:
    ///     - app: The app identifier expected by the `occ` command line.
    ///     - id: The Docker container identifier to run the command in.
    ///
    /// - Throws: A `DockerClientError` if the command cannot be run or exits with a non-zero status.
    ///
    public static func addApp(_ app: String, inContainer id: String) async throws {
        try await runOCC(["app:install", app], inContainer: id)
    }

    ///
    /// Removes a Nextcloud app by executing `occ app:remove` in the container with the given identifier.
    ///
    /// - Parameters:
    ///     - app: The app identifier expected by the `occ` command line.
    ///     - id: The Docker container identifier to run the command in.
    ///
    /// - Throws: A `DockerClientError` if the command cannot be run or exits with a non-zero status.
    ///
    public static func removeApp(_ app: String, inContainer id: String) async throws {
        try await runOCC(["app:remove", app], inContainer: id)
    }

    ///
    /// Enables a Nextcloud app by executing `occ app:enable` in the container with the given identifier.
    ///
    /// - Parameters:
    ///     - app: The app identifier expected by the `occ` command line.
    ///     - id: The Docker container identifier to run the command in.
    ///
    /// - Throws: A `DockerClientError` if the command cannot be run or exits with a non-zero status.
    ///
    public static func enableApp(_ app: String, inContainer id: String) async throws {
        try await runOCC(["app:enable", app], inContainer: id)
    }

    ///
    /// Disables a Nextcloud app by executing `occ app:disable` in the container with the given identifier.
    ///
    /// - Parameters:
    ///     - app: The app identifier expected by the `occ` command line.
    ///     - id: The Docker container identifier to run the command in.
    ///
    /// - Throws: A `DockerClientError` if the command cannot be run or exits with a non-zero status.
    ///
    public static func disableApp(_ app: String, inContainer id: String) async throws {
        try await runOCC(["app:disable", app], inContainer: id)
    }

    // MARK: - User management

    ///
    /// Adds a Nextcloud user by executing `occ user:add` in the container with the given identifier.
    ///
    /// The user identifier is reused as the account password, which is safe for the local, throwaway test environments this package targets. The password is passed via the `OC_PASS` environment variable and the `--password-from-env` flag so that `occ` runs non-interactively.
    ///
    /// - Parameters:
    ///     - user: The user identifier expected by the `occ` command line.
    ///     - id: The Docker container identifier to run the command in.
    ///
    /// - Throws: A `DockerClientError` if the command cannot be run or exits with a non-zero status.
    ///
    public static func addUser(_ user: String, inContainer id: String) async throws {
        try await runOCC(["user:add", "--password-from-env", user], environment: ["OC_PASS=\(user)"], inContainer: id)
    }

    ///
    /// Removes a Nextcloud user by executing `occ user:delete` in the container with the given identifier.
    ///
    /// - Parameters:
    ///     - user: The user identifier expected by the `occ` command line.
    ///     - id: The Docker container identifier to run the command in.
    ///
    /// - Throws: A `DockerClientError` if the command cannot be run or exits with a non-zero status.
    ///
    public static func removeUser(_ user: String, inContainer id: String) async throws {
        try await runOCC(["user:delete", user], inContainer: id)
    }

    ///
    /// Enables a Nextcloud user by executing `occ user:enable` in the container with the given identifier.
    ///
    /// - Parameters:
    ///     - user: The user identifier expected by the `occ` command line.
    ///     - id: The Docker container identifier to run the command in.
    ///
    /// - Throws: A `DockerClientError` if the command cannot be run or exits with a non-zero status.
    ///
    public static func enableUser(_ user: String, inContainer id: String) async throws {
        try await runOCC(["user:enable", user], inContainer: id)
    }

    ///
    /// Disables a Nextcloud user by executing `occ user:disable` in the container with the given identifier.
    ///
    /// - Parameters:
    ///     - user: The user identifier expected by the `occ` command line.
    ///     - id: The Docker container identifier to run the command in.
    ///
    /// - Throws: A `DockerClientError` if the command cannot be run or exits with a non-zero status.
    ///
    public static func disableUser(_ user: String, inContainer id: String) async throws {
        try await runOCC(["user:disable", user], inContainer: id)
    }

    // MARK: - Command execution

    ///
    /// Runs an `occ` command as `www-data` inside the container with the given identifier and waits for it to finish.
    ///
    /// The given `arguments` are appended to `php occ` and executed from the Nextcloud web root at `/var/www/html`.
    ///
    /// - Parameters:
    ///     - arguments: The `occ` subcommand and its arguments, e.g. `["app:install", "calendar"]`.
    ///     - environment: Environment variables in `VAR=value` form to expose to the command, e.g. `["OC_PASS=secret"]`.
    ///     - id: The Docker container identifier to run the command in.
    ///
    /// - Throws: `DockerClientError.unexpectedStatusCode` if the Docker Engine API rejects the request, `DockerClientError.timeout` if the command does not finish within 30 seconds, or `DockerClientError.commandFailed` if it exits with a non-zero status.
    ///
    private static func runOCC(_ arguments: [String], environment: [String] = [], inContainer id: String) async throws {
        let client = try await makeDockerEngineClient()

        // 1. Create the exec instance.
        let createRequest = CreateExecRequest(Cmd: ["php", "occ"] + arguments, User: "www-data", WorkingDir: "/var/www/html", Env: environment.isEmpty ? nil : environment)
        let createResponse = try await client.post(path: "/containers/\(id)/exec", body: createRequest)

        guard createResponse.statusCode == 201 else {
            let message = String(data: createResponse.body, encoding: .utf8) ?? "<no body>"
            throw DockerClientError.unexpectedStatusCode(createResponse.statusCode, message)
        }

        let created = try JSONDecoder().decode(CreateExecResponse.self, from: createResponse.body)

        // 2. Start the exec instance in detached mode.
        let startRequest = StartExecRequest(Detach: true)
        let startResponse = try await client.post(path: "/exec/\(created.Id)/start", body: startRequest)

        guard startResponse.statusCode == 200 else {
            let message = String(data: startResponse.body, encoding: .utf8) ?? "<no body>"
            throw DockerClientError.unexpectedStatusCode(startResponse.statusCode, message)
        }

        // 3. Wait for the command to finish (up to 30 seconds), then confirm that it exited successfully.
        let execDeadline = Date().addingTimeInterval(30)

        while Date() < execDeadline {
            let inspectResponse = try await client.get(path: "/exec/\(created.Id)/json")
            let info = try JSONDecoder().decode(ExecInspectResponse.self, from: inspectResponse.body)

            if !info.Running {
                if let exitCode = info.ExitCode, exitCode != 0 {
                    throw DockerClientError.commandFailed(command: arguments, exitCode: exitCode)
                }

                return
            }

            try await Task.sleep(for: .milliseconds(100))
        }

        throw DockerClientError.timeout
    }

    // MARK: - Provisioning

    ///
    /// Runs all post-deployment provisioning steps defined in the container's configuration.
    ///
    /// After waiting for the Nextcloud instance to finish its initial installation, this disables the apps listed in ``NextcloudConfiguration/disabledApps``, enables the apps listed in ``NextcloudConfiguration/enabledApps`` (installing them first when necessary), and creates the users listed in ``NextcloudConfiguration/users``.
    ///
    private static func provision(_ container: NextcloudContainer) async throws {
        let configuration = container.configuration

        guard !configuration.disabledApps.isEmpty || !configuration.enabledApps.isEmpty || !configuration.users.isEmpty else {
            return
        }

        try await waitUntilReady(port: container.port)

        for app in configuration.disabledApps {
            // A single broken app must not interrupt the remaining provisioning steps, so failures are intentionally ignored here.
            try? await disableApp(app, inContainer: container.id)
        }

        for app in configuration.enabledApps {
            // Enabling fails when the app is not present yet, in which case it is installed from the app store, which also enables it.
            do {
                try await enableApp(app, inContainer: container.id)
            } catch {
                try await addApp(app, inContainer: container.id)
            }
        }

        for user in configuration.users {
            try await addUser(user, inContainer: container.id)
        }
    }

    ///
    /// Polls the Nextcloud `status.php` endpoint on the given host port until the instance reports itself as installed, or a timeout is reached.
    ///
    /// - Parameters:
    ///     - port: The host port the container's HTTP port 80 is mapped to.
    ///
    /// - Throws: ``DockerClientError/timeout`` when the instance does not become ready within 120 seconds.
    ///
    private static func waitUntilReady(port: UInt) async throws {
        let url = URL(string: "http://localhost:\(port)/status.php")!
        let deadline = Date().addingTimeInterval(120)

        while Date() < deadline {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let status = try JSONDecoder().decode(NextcloudStatus.self, from: data)

                if status.installed {
                    return
                }
            } catch {
                // Nextcloud is not ready yet – retry after a short delay.
            }

            try await Task.sleep(for: .milliseconds(500))
        }

        throw DockerClientError.timeout
    }
}
