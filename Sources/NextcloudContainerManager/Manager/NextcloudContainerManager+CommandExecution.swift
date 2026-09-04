// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Command execution for ``NextcloudContainerManager``.
///
/// These functions run commands inside a container through the Docker Engine exec API. They back the app, user and High Performance Backend operations, and they are public in their own right so that a caller needing an `occ` subcommand this package does not wrap can reach for one instead of driving the `docker` command line tool alongside it.
///
public extension NextcloudContainerManager {
    ///
    /// How long a command may produce nothing before it is given up on, unless the caller asks for something else.
    ///
    /// This is the allowance every command that runs entirely inside the container is given, which is all of them except app installation. Those commands finish in well under a second, so the value is not a budget to be spent but the point at which a wedged command is reported instead of waited on. App installation reaches the network and is given ``defaultAppInstallationTimeout`` instead.
    ///
    static let defaultCommandTimeout: TimeInterval = 30

    ///
    /// Runs an `occ` command as `www-data` inside the container with the given identifier and waits for it to finish.
    ///
    /// The given `arguments` are appended to `php occ` and executed from the Nextcloud web root at `/var/www/html` through ``runExec(_:user:workingDirectory:environment:waitsForExit:timeout:inContainer:)``.
    ///
    /// This is the general way in: the app and user functions on ``NextcloudContainerManager`` are wrappers around the handful of subcommands they name, and anything else `occ` can do is reachable here without leaving the library.
    ///
    /// ```swift
    /// let result = try await NextcloudContainerManager.runOCC(["user:list", "--output=json"], inContainer: container.id)
    /// print(result.standardOutput)
    /// ```
    ///
    /// - Parameters:
    ///     - arguments: The `occ` subcommand and its arguments, e.g. `["app:install", "calendar"]`.
    ///     - environment: Environment variables in `VAR=value` form to expose to the command, e.g. `["OC_PASS=secret"]`.
    ///     - timeout: How long the command may produce nothing before it is given up on, or `nil` to wait for as long as it takes. Defaults to ``defaultCommandTimeout``.
    ///     - id: The Docker container identifier to run the command in.
    ///
    /// - Returns: What the command wrote to its output streams.
    ///
    /// - Throws: ``NextcloudContainerManagerError/commandFailed(command:result:)`` if the command exits with a non-zero status, ``NextcloudContainerManagerError/commandTimedOut(command:)`` if it produces nothing within `timeout`, `CancellationError` if the surrounding task is cancelled while waiting, or a `DockerClientError` for any API-level failure.
    ///
    @discardableResult
    static func runOCC(_ arguments: [String], environment: [String] = [], timeout: TimeInterval? = defaultCommandTimeout, inContainer id: String) async throws -> CommandResult {
        try await runExec(["php", "occ"] + arguments, environment: environment, timeout: timeout, inContainer: id)
    }

    ///
    /// Runs a command inside the container with the given identifier, optionally waiting for it to finish.
    ///
    /// This is the shared transport behind ``runOCC(_:environment:timeout:inContainer:)`` and the push daemon launch. A waited command is attached to, so the Docker Engine holds the connection open until it exits and hands over everything it wrote on the way; the exit status is read from the exec instance afterwards. When `waitsForExit` is `false` the command is started detached and the method returns immediately with an empty result, which is required for long-running processes such as the push daemon that never exit on their own.
    ///
    /// The exit status is the authority on the outcome and `timeout` only bounds how long the wait for it lasts. It is a bound on silence rather than on total duration — the point at which a command that has produced nothing is presumed stuck — which is what can be enforced without guessing how long legitimate work should take. For `occ` the distinction rarely matters, because it reports at the end rather than as it goes, so the allowance is in practice the whole wait. Passing `nil` gives up the bound entirely while keeping the exit-status check, which is the honest option for a command whose duration the caller cannot predict, such as an app-store download over a slow link.
    ///
    /// - Parameters:
    ///     - command: The command and its arguments, e.g. `["php", "occ", "status"]`.
    ///     - user: The user to run the command as. Defaults to `www-data`.
    ///     - workingDirectory: The working directory for the command. Defaults to the Nextcloud web root at `/var/www/html`.
    ///     - environment: Environment variables in `VAR=value` form to expose to the command.
    ///     - waitsForExit: Whether to wait for the command to finish and verify its exit status. Defaults to `true`.
    ///     - timeout: How long the command may produce nothing before it is given up on, or `nil` to wait for as long as it takes. A value of zero or less leaves it no time at all. Ignored when `waitsForExit` is `false`. Defaults to ``defaultCommandTimeout``.
    ///     - id: The Docker container identifier to run the command in.
    ///
    /// - Returns: What the command wrote to its output streams, or an empty result when `waitsForExit` is `false` and there was nothing to wait for.
    ///
    /// - Throws: ``NextcloudContainerManagerError/commandFailed(command:result:)`` if the command exits with a non-zero status, ``NextcloudContainerManagerError/commandTimedOut(command:)`` if it produces nothing within `timeout`, `CancellationError` if the surrounding task is cancelled while waiting, or a `DockerClientError` for any API-level failure.
    ///
    @discardableResult
    static func runExec(_ command: [String], user: String = "www-data", workingDirectory: String = "/var/www/html", environment: [String] = [], waitsForExit: Bool = true, timeout: TimeInterval? = defaultCommandTimeout, inContainer id: String) async throws -> CommandResult {
        let client = try await makeDockerEngineClient()

        // 1. Create the exec instance, asking for its output only when there will be someone to read it.
        let createRequest = CreateExecRequest(Cmd: command, User: user, WorkingDir: workingDirectory, Env: environment.isEmpty ? nil : environment, AttachStdout: waitsForExit, AttachStderr: waitsForExit)
        let createResponse = try await client.post(path: "/containers/\(id)/exec", body: createRequest)

        guard createResponse.statusCode == 201 else {
            let message = String(data: createResponse.body, encoding: .utf8) ?? "<no body>"
            throw DockerClientError.unexpectedStatusCode(createResponse.statusCode, message)
        }

        let created = try JSONDecoder().decode(CreateExecResponse.self, from: createResponse.body)

        // 2. Long-running commands such as the push daemon never exit, so they are started detached and left alone.
        guard waitsForExit else {
            let startResponse = try await client.post(path: "/exec/\(created.Id)/start", body: StartExecRequest(Detach: true, Tty: false))

            guard startResponse.statusCode == 200 else {
                let message = String(data: startResponse.body, encoding: .utf8) ?? "<no body>"
                throw DockerClientError.unexpectedStatusCode(startResponse.statusCode, message)
            }

            return CommandResult(exitCode: 0, standardOutput: "", standardError: "")
        }

        // 3. Start the command attached, which both waits for it and collects what it wrote.
        // The socket cannot express "no time at all" — a zero interval means no deadline to the kernel — so a non-positive or otherwise unusable allowance is clamped to the smallest one that still expires. The literal comes first because max returns its first argument when the second is not a number.
        let allowance = timeout.map { max(0.001, $0) }
        let stream: (statusCode: Int, body: Data)

        do {
            stream = try await client.post(path: "/exec/\(created.Id)/start", body: StartExecRequest(Detach: false, Tty: false), timeout: allowance)
        } catch DockerClientError.requestTimedOut {
            throw NextcloudContainerManagerError.commandTimedOut(command: command)
        }

        guard stream.statusCode == 200 else {
            let message = String(data: stream.body, encoding: .utf8) ?? "<no body>"
            throw DockerClientError.unexpectedStatusCode(stream.statusCode, message)
        }

        let streams = demultiplexDockerStream(stream.body)

        let result = try await CommandResult(
            exitCode: exitCode(ofExec: created.Id, using: client),
            standardOutput: String(decoding: streams.standardOutput, as: UTF8.self),
            standardError: String(decoding: streams.standardError, as: UTF8.self)
        )

        guard result.exitCode == 0 else {
            throw NextcloudContainerManagerError.commandFailed(command: command, result: result)
        }

        return result
    }
}

extension NextcloudContainerManager {
    ///
    /// Reads the status an exec instance exited with.
    ///
    /// The output stream of an attached command closes when the command exits, but the exec instance is not necessarily marked as finished by the time the last byte arrives, so it is polled briefly rather than read once. The wait is short because the command has demonstrably ended already — what is being waited for is the Docker Engine writing that down.
    ///
    /// - Parameters:
    ///     - id: The exec instance identifier.
    ///     - client: The Docker Engine client to use.
    ///
    /// - Returns: The exit status, or zero if the Docker Engine reports none.
    ///
    private static func exitCode(ofExec id: String, using client: DockerEngineClient) async throws -> Int {
        let deadline = Date().addingTimeInterval(5)

        while true {
            let response = try await client.get(path: "/exec/\(id)/json")

            // The exec instance disappears together with its container, so a container removed underneath a command has to be reported as the missing resource it is rather than as an undecodable response body.
            guard response.statusCode == 200 else {
                let message = String(data: response.body, encoding: .utf8) ?? "<no body>"
                throw DockerClientError.unexpectedStatusCode(response.statusCode, message)
            }

            let info = try JSONDecoder().decode(ExecInspectResponse.self, from: response.body)

            if !info.Running {
                return info.ExitCode ?? 0
            }

            if Date() >= deadline {
                throw DockerClientError.timeout
            }

            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
