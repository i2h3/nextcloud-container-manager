// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Command execution for ``NextcloudContainerManager``.
///
/// These functions are the shared transport that runs commands inside a container through the Docker Engine exec API. They back the app, user and High Performance Backend operations and live in a dedicated file to keep that plumbing separate from the core container lifecycle in ``NextcloudContainerManager``.
///
extension NextcloudContainerManager {
    ///
    /// Runs an `occ` command as `www-data` inside the container with the given identifier and waits for it to finish.
    ///
    /// The given `arguments` are appended to `php occ` and executed from the Nextcloud web root at `/var/www/html` through ``runExec(_:user:workingDirectory:environment:waitsForExit:inContainer:)``.
    ///
    /// - Parameters:
    ///     - arguments: The `occ` subcommand and its arguments, e.g. `["app:install", "calendar"]`.
    ///     - environment: Environment variables in `VAR=value` form to expose to the command, e.g. `["OC_PASS=secret"]`.
    ///     - id: The Docker container identifier to run the command in.
    ///
    /// - Throws: `DockerClientError.unexpectedStatusCode` if the Docker Engine API rejects the request, `DockerClientError.timeout` if the command does not finish within 30 seconds, or `DockerClientError.commandFailed` if it exits with a non-zero status.
    ///
    static func runOCC(_ arguments: [String], environment: [String] = [], inContainer id: String) async throws {
        try await runExec(["php", "occ"] + arguments, environment: environment, inContainer: id)
    }

    ///
    /// Runs a command inside the container with the given identifier, optionally waiting for it to finish.
    ///
    /// This is the shared transport behind ``runOCC(_:environment:inContainer:)`` and the push daemon launch. The exec instance is always started detached; when `waitsForExit` is `false` the method returns immediately, which is required for long-running processes such as the push daemon that never exit on their own.
    ///
    /// - Parameters:
    ///     - command: The command and its arguments, e.g. `["php", "occ", "status"]`.
    ///     - user: The user to run the command as. Defaults to `www-data`.
    ///     - workingDirectory: The working directory for the command. Defaults to the Nextcloud web root at `/var/www/html`.
    ///     - environment: Environment variables in `VAR=value` form to expose to the command.
    ///     - waitsForExit: Whether to wait for the command to finish and verify its exit code. Defaults to `true`.
    ///     - id: The Docker container identifier to run the command in.
    ///
    /// - Throws: `DockerClientError.unexpectedStatusCode` if the Docker Engine API rejects the request, `DockerClientError.timeout` if a waited command does not finish within 30 seconds, or `DockerClientError.commandFailed` if it exits with a non-zero status.
    ///
    static func runExec(_ command: [String], user: String = "www-data", workingDirectory: String = "/var/www/html", environment: [String] = [], waitsForExit: Bool = true, inContainer id: String) async throws {
        let client = try await makeDockerEngineClient()

        // 1. Create the exec instance.
        let createRequest = CreateExecRequest(Cmd: command, User: user, WorkingDir: workingDirectory, Env: environment.isEmpty ? nil : environment)
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

        // 3. Long-running commands such as the push daemon never exit, so skip the completion check for them.
        guard waitsForExit else {
            return
        }

        // 4. Wait for the command to finish (up to 30 seconds), then confirm that it exited successfully.
        let execDeadline = Date().addingTimeInterval(30)

        while Date() < execDeadline {
            let inspectResponse = try await client.get(path: "/exec/\(created.Id)/json")
            let info = try JSONDecoder().decode(ExecInspectResponse.self, from: inspectResponse.body)

            if !info.Running {
                if let exitCode = info.ExitCode, exitCode != 0 {
                    throw DockerClientError.commandFailed(command: command, exitCode: exitCode)
                }

                return
            }

            try await Task.sleep(for: .milliseconds(100))
        }

        throw DockerClientError.timeout
    }
}
