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
    /// How long a command is waited on by default before it is reported as timed out.
    ///
    /// This is the allowance every command that runs entirely inside the container is given, which is all of them except app installation. Those commands finish in well under a second, so the value is not a budget to be spent but the point at which a wedged command is reported instead of waited on. App installation reaches the network and is given ``defaultAppInstallationTimeout`` instead.
    ///
    public static let defaultCommandTimeout: TimeInterval = 30

    ///
    /// Runs an `occ` command as `www-data` inside the container with the given identifier and waits for it to finish.
    ///
    /// The given `arguments` are appended to `php occ` and executed from the Nextcloud web root at `/var/www/html` through ``runExec(_:user:workingDirectory:environment:waitsForExit:timeout:inContainer:)``.
    ///
    /// - Parameters:
    ///     - arguments: The `occ` subcommand and its arguments, e.g. `["app:install", "calendar"]`.
    ///     - environment: Environment variables in `VAR=value` form to expose to the command, e.g. `["OC_PASS=secret"]`.
    ///     - timeout: How long to wait for the command to finish, or `nil` to wait for as long as it takes. Defaults to ``defaultCommandTimeout``.
    ///     - id: The Docker container identifier to run the command in.
    ///
    /// - Throws: `DockerClientError.unexpectedStatusCode` if the Docker Engine API rejects the request, `DockerClientError.timeout` if the command does not finish within `timeout`, or `DockerClientError.commandFailed` if it exits with a non-zero status.
    ///
    static func runOCC(_ arguments: [String], environment: [String] = [], timeout: TimeInterval? = defaultCommandTimeout, inContainer id: String) async throws {
        try await runExec(["php", "occ"] + arguments, environment: environment, timeout: timeout, inContainer: id)
    }

    ///
    /// Runs a command inside the container with the given identifier, optionally waiting for it to finish.
    ///
    /// This is the shared transport behind ``runOCC(_:environment:timeout:inContainer:)`` and the push daemon launch. The exec instance is always started detached; when `waitsForExit` is `false` the method returns immediately, which is required for long-running processes such as the push daemon that never exit on their own.
    ///
    /// A waited command is polled until it reports itself as no longer running, and it is inspected at least once regardless of `timeout`, so a command which has already finished is never reported as timed out. The exit code is therefore the authority on the outcome and the deadline only bounds how long the wait for it lasts. Passing `nil` gives up that bound in exchange for keeping the exit-code check, which is the right trade for a command whose duration the caller cannot predict, such as an app-store download over a slow link.
    ///
    /// - Parameters:
    ///     - command: The command and its arguments, e.g. `["php", "occ", "status"]`.
    ///     - user: The user to run the command as. Defaults to `www-data`.
    ///     - workingDirectory: The working directory for the command. Defaults to the Nextcloud web root at `/var/www/html`.
    ///     - environment: Environment variables in `VAR=value` form to expose to the command.
    ///     - waitsForExit: Whether to wait for the command to finish and verify its exit code. Defaults to `true`.
    ///     - timeout: How long to wait for the command to finish, or `nil` to wait for as long as it takes. A value of zero or less waits not at all and inspects the command exactly once. Ignored when `waitsForExit` is `false`. Defaults to ``defaultCommandTimeout``.
    ///     - id: The Docker container identifier to run the command in.
    ///
    /// - Throws: `DockerClientError.unexpectedStatusCode` if the Docker Engine API rejects the request, `DockerClientError.timeout` if a waited command does not finish within `timeout`, `DockerClientError.commandFailed` if it exits with a non-zero status, or `CancellationError` if the surrounding task is cancelled while waiting.
    ///
    static func runExec(_ command: [String], user: String = "www-data", workingDirectory: String = "/var/www/html", environment: [String] = [], waitsForExit: Bool = true, timeout: TimeInterval? = defaultCommandTimeout, inContainer id: String) async throws {
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

        // 4. Wait for the command to finish, then confirm that it exited successfully.
        // The deadline is computed once so that the elapsed inspections cannot extend it, and clamping to zero folds a negative or otherwise unusable interval into the same single inspection a zero interval gets, rather than into a deadline no moment in time ever satisfies.
        let deadline = timeout.map { Date().addingTimeInterval(max(0, $0)) }

        while true {
            try Task.checkCancellation()

            let inspectResponse = try await client.get(path: "/exec/\(created.Id)/json")

            // The exec instance disappears together with its container, and the wait can now last for as long as the caller allows, so a container removed underneath a long installation must be reported as the missing resource it is rather than as an undecodable response body.
            guard inspectResponse.statusCode == 200 else {
                let message = String(data: inspectResponse.body, encoding: .utf8) ?? "<no body>"
                throw DockerClientError.unexpectedStatusCode(inspectResponse.statusCode, message)
            }

            let info = try JSONDecoder().decode(ExecInspectResponse.self, from: inspectResponse.body)

            if !info.Running {
                if let exitCode = info.ExitCode, exitCode != 0 {
                    throw DockerClientError.commandFailed(command: command, exitCode: exitCode)
                }

                return
            }

            // The deadline is consulted only after the command has been given its chance to report an exit code, so the clock can never overrule a command which has in fact already finished.
            if let deadline, Date() >= deadline {
                throw DockerClientError.timeout
            }

            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}
