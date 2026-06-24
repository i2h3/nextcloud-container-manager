// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The interface of an individual test container deployment representation.
///
public struct NextcloudContainer: Identifiable, Sendable {
    ///
    /// The initial configuration this container was created with.
    ///
    public let configuration: NextcloudConfiguration

    ///
    /// The unique Docker container identifier.
    ///
    public let id: String

    ///
    /// The host port mapped to the container's HTTP port 80.
    ///
    public let port: UInt

    /// The Docker Engine client used to communicate with the daemon.
    let client: DockerEngineClient

    ///
    /// Stops this container and deletes all associated data.
    ///
    /// Delegates to ``NextcloudContainerManager/delete(_:)``.
    ///
    public func delete() async throws {
        try await NextcloudContainerManager.delete(id)
    }

    // MARK: - Provisioning

    ///
    /// Runs all post-deployment provisioning steps defined in the configuration.
    ///
    /// Currently this waits for the Nextcloud instance to finish its initial
    /// installation and then disables the apps listed in
    /// ``NextcloudConfiguration/disabledApps``.
    ///
    func provision() async throws {
        guard !configuration.disabledApps.isEmpty else {
            return
        }

        try await waitUntilReady()

        for app in configuration.disabledApps {
            // A single broken app must not interrupt the remaining provisioning steps, so failures are intentionally ignored here.
            try? await disableApp(app)
        }
    }

    // MARK: - Status polling

    ///
    /// Polls the Nextcloud `status.php` endpoint until the instance reports
    /// itself as installed, or a timeout is reached.
    ///
    /// - Throws: ``DockerClientError/timeout`` when the instance does not
    ///   become ready within 120 seconds.
    ///
    private func waitUntilReady() async throws {
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

            try await Task.sleep(for: .seconds(2))
        }

        throw DockerClientError.timeout
    }

    // MARK: - App management

    ///
    /// Installs a Nextcloud app by executing `occ app:install` inside the container.
    ///
    /// - Parameters:
    ///     - app: The app identifier expected by the `occ` command line.
    ///
    /// - Throws: A `DockerClientError` if the command cannot be run or exits with a non-zero status.
    ///
    public func addApp(_ app: String) async throws {
        try await runOCC(["app:install", app])
    }

    ///
    /// Removes a Nextcloud app by executing `occ app:remove` inside the container.
    ///
    /// - Parameters:
    ///     - app: The app identifier expected by the `occ` command line.
    ///
    /// - Throws: A `DockerClientError` if the command cannot be run or exits with a non-zero status.
    ///
    public func removeApp(_ app: String) async throws {
        try await runOCC(["app:remove", app])
    }

    ///
    /// Enables a Nextcloud app by executing `occ app:enable` inside the container.
    ///
    /// - Parameters:
    ///     - app: The app identifier expected by the `occ` command line.
    ///
    /// - Throws: A `DockerClientError` if the command cannot be run or exits with a non-zero status.
    ///
    public func enableApp(_ app: String) async throws {
        try await runOCC(["app:enable", app])
    }

    ///
    /// Disables a Nextcloud app by executing `occ app:disable` inside the container.
    ///
    /// - Parameters:
    ///     - app: The app identifier expected by the `occ` command line.
    ///
    /// - Throws: A `DockerClientError` if the command cannot be run or exits with a non-zero status.
    ///
    public func disableApp(_ app: String) async throws {
        try await runOCC(["app:disable", app])
    }

    // MARK: - User management

    ///
    /// Adds a Nextcloud user by executing `occ user:add` inside the container.
    ///
    /// The user identifier is reused as the account password, which is safe for the local, throwaway test environments this package targets.
    /// The password is passed via the `OC_PASS` environment variable and the `--password-from-env` flag so that `occ` runs non-interactively.
    ///
    /// - Parameters:
    ///     - user: The user identifier expected by the `occ` command line.
    ///
    /// - Throws: A `DockerClientError` if the command cannot be run or exits with a non-zero status.
    ///
    public func addUser(_ user: String) async throws {
        try await runOCC(["user:add", "--password-from-env", user], environment: ["OC_PASS=\(user)"])
    }

    ///
    /// Removes a Nextcloud user by executing `occ user:delete` inside the container.
    ///
    /// - Parameters:
    ///     - user: The user identifier expected by the `occ` command line.
    ///
    /// - Throws: A `DockerClientError` if the command cannot be run or exits with a non-zero status.
    ///
    public func removeUser(_ user: String) async throws {
        try await runOCC(["user:delete", user])
    }

    ///
    /// Enables a Nextcloud user by executing `occ user:enable` inside the container.
    ///
    /// - Parameters:
    ///     - user: The user identifier expected by the `occ` command line.
    ///
    /// - Throws: A `DockerClientError` if the command cannot be run or exits with a non-zero status.
    ///
    public func enableUser(_ user: String) async throws {
        try await runOCC(["user:enable", user])
    }

    ///
    /// Disables a Nextcloud user by executing `occ user:disable` inside the container.
    ///
    /// - Parameters:
    ///     - user: The user identifier expected by the `occ` command line.
    ///
    /// - Throws: A `DockerClientError` if the command cannot be run or exits with a non-zero status.
    ///
    public func disableUser(_ user: String) async throws {
        try await runOCC(["user:disable", user])
    }

    // MARK: - Command execution

    ///
    /// Runs an `occ` command inside the container as `www-data` and waits for it to finish.
    ///
    /// The given `arguments` are appended to `php occ` and executed from the Nextcloud web root at `/var/www/html`.
    ///
    /// - Parameters:
    ///     - arguments: The `occ` subcommand and its arguments, e.g. `["app:install", "calendar"]`.
    ///     - environment: Environment variables in `VAR=value` form to expose to the command, e.g. `["OC_PASS=secret"]`.
    ///
    /// - Throws: `DockerClientError.unexpectedStatusCode` if the Docker Engine API rejects the request, `DockerClientError.timeout` if the command does not finish within 30 seconds, or `DockerClientError.commandFailed` if it exits with a non-zero status.
    ///
    private func runOCC(_ arguments: [String], environment: [String] = []) async throws {
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
                guard info.ExitCode == 0 else {
                    throw DockerClientError.commandFailed(command: arguments, exitCode: info.ExitCode)
                }

                return
            }

            try await Task.sleep(for: .seconds(1))
        }

        throw DockerClientError.timeout
    }
}
