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
    /// The given `arguments` are appended to `php occ` and executed from the Nextcloud web root at `/var/www/html`.
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
    /// - Returns: What the command wrote to its output streams. An `occ` command is always waited for, so there is always a result.
    ///
    /// - Throws: ``NextcloudContainerManagerError/commandFailed(command:result:)`` if the command exits with a non-zero status, ``NextcloudContainerManagerError/commandTimedOut(command:)`` if it produces nothing within `timeout`, ``NextcloudContainerManagerError/commandStatusUnavailable(command:)`` if it finishes without the Docker Engine reporting a status, `CancellationError` if the surrounding task is cancelled while waiting, or another case of ``NextcloudContainerManagerError`` for a Docker Engine request that fails, times out or cannot be made.
    ///
    @discardableResult
    static func runOCC(_ arguments: [String], environment: [String] = [], timeout: TimeInterval? = defaultCommandTimeout, inContainer id: String) async throws -> CommandResult {
        try await runWaitedExec(["php", "occ"] + arguments, environment: environment, timeout: timeout, inContainer: id)
    }

    ///
    /// Runs a command inside the container with the given identifier, optionally waiting for it to finish.
    ///
    /// This is the shared transport behind ``runOCC(_:environment:timeout:inContainer:)`` and the push daemon launch. A waited command is attached to, so the Docker Engine holds the connection open until it exits and hands over everything it wrote; the exit status is read from the exec instance afterwards.
    ///
    /// When `waitsForExit` is `false` the command is started detached and the method returns `nil` at once, which is required for long-running processes such as the push daemon that never exit on their own. There is no status to report for a command that has not exited, so none is invented — the absence of a result is the honest answer, and a caller that only wants the effect can ignore it.
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
    /// - Returns: What the command wrote to its output streams, or `nil` when `waitsForExit` is `false` and the command was left running.
    ///
    /// - Throws: ``NextcloudContainerManagerError/commandFailed(command:result:)`` if the command exits with a non-zero status, ``NextcloudContainerManagerError/commandTimedOut(command:)`` if it produces nothing within `timeout`, ``NextcloudContainerManagerError/commandStatusUnavailable(command:)`` if it finishes without the Docker Engine reporting a status, `CancellationError` if the surrounding task is cancelled while waiting, or another case of ``NextcloudContainerManagerError`` for a Docker Engine request that fails, times out or cannot be made.
    ///
    @discardableResult
    static func runExec(_ command: [String], user: String = "www-data", workingDirectory: String = "/var/www/html", environment: [String] = [], waitsForExit: Bool = true, timeout: TimeInterval? = defaultCommandTimeout, inContainer id: String) async throws -> CommandResult? {
        guard waitsForExit else {
            try await startDetachedExec(command, user: user, workingDirectory: workingDirectory, environment: environment, inContainer: id)

            return nil
        }

        return try await runWaitedExec(command, user: user, workingDirectory: workingDirectory, environment: environment, timeout: timeout, inContainer: id)
    }
}

extension NextcloudContainerManager {
    ///
    /// Creates an exec instance and returns its identifier.
    ///
    /// Output exists only for the duration of the stream that starting the instance answers with, and the Docker Engine keeps none of it afterwards, so it has to be asked for here — before the command runs — and is left off for one that will be started detached and never read.
    ///
    /// - Parameters:
    ///     - command: The command and its arguments.
    ///     - user: The user to run the command as.
    ///     - workingDirectory: The working directory for the command.
    ///     - environment: Environment variables in `VAR=value` form to expose to the command.
    ///     - attachesOutput: Whether the command's output streams are connected to the response that starting it answers with.
    ///     - id: The Docker container identifier to run the command in.
    ///     - client: The Docker Engine client to use.
    ///
    /// - Returns: The identifier of the exec instance.
    ///
    private static func createExec(_ command: [String], user: String, workingDirectory: String, environment: [String], attachesOutput: Bool, inContainer id: String, using client: DockerEngineClient) async throws -> String {
        let request = CreateExecRequest(Cmd: command, User: user, WorkingDir: workingDirectory, Env: environment.isEmpty ? nil : environment, AttachStdout: attachesOutput, AttachStderr: attachesOutput)
        let response = try await client.post(path: "/containers/\(id)/exec", body: request)

        try response.checked([201])

        return try response.decode(CreateExecResponse.self).Id
    }

    ///
    /// Starts a command and leaves it running.
    ///
    /// This is the path for a process that never exits on its own, such as the push daemon, where waiting for a status would mean waiting forever.
    ///
    /// - Parameters:
    ///     - command: The command and its arguments.
    ///     - user: The user to run the command as.
    ///     - workingDirectory: The working directory for the command.
    ///     - environment: Environment variables in `VAR=value` form to expose to the command.
    ///     - id: The Docker container identifier to run the command in.
    ///
    private static func startDetachedExec(_ command: [String], user: String, workingDirectory: String, environment: [String], inContainer id: String) async throws {
        let client = try await makeDockerEngineClient()
        let exec = try await createExec(command, user: user, workingDirectory: workingDirectory, environment: environment, attachesOutput: false, inContainer: id, using: client)
        let response = try await client.post(path: "/exec/\(exec)/start", body: StartExecRequest(Detach: true, Tty: false))

        try response.checked([200])
    }

    ///
    /// Runs a command, waits for it to finish, and collects what it wrote.
    ///
    /// - Parameters:
    ///     - command: The command and its arguments.
    ///     - user: The user to run the command as.
    ///     - workingDirectory: The working directory for the command.
    ///     - environment: Environment variables in `VAR=value` form to expose to the command.
    ///     - timeout: How long the command may produce nothing before it is given up on, or `nil` to wait for as long as it takes.
    ///     - id: The Docker container identifier to run the command in.
    ///
    /// - Returns: What the command wrote to its output streams.
    ///
    private static func runWaitedExec(_ command: [String], user: String = "www-data", workingDirectory: String = "/var/www/html", environment: [String] = [], timeout: TimeInterval?, inContainer id: String) async throws -> CommandResult {
        let client = try await makeDockerEngineClient()
        let exec = try await createExec(command, user: user, workingDirectory: workingDirectory, environment: environment, attachesOutput: true, inContainer: id, using: client)

        // The socket cannot express "no time at all" — a zero interval means no deadline to the kernel — so a non-positive or otherwise unusable allowance is clamped to the smallest one that still expires. The literal comes first because max returns its first argument when the second is not a number.
        let allowance = timeout.map { max(0.001, $0) }
        let stream: EngineResponse

        do {
            stream = try await client.post(path: "/exec/\(exec)/start", body: StartExecRequest(Detach: false, Tty: false), timeout: allowance)
        } catch NextcloudContainerManagerError.engineRequestTimedOut {
            throw NextcloudContainerManagerError.commandTimedOut(command: command)
        }

        try stream.checked([200])

        let streams = demultiplexDockerStream(stream.body)

        let result = try await CommandResult(exitCode: exitCode(ofExec: exec, running: command, using: client), standardOutput: String(decoding: streams.standardOutput, as: UTF8.self), standardError: String(decoding: streams.standardError, as: UTF8.self))

        guard result.exitCode == 0 else {
            throw NextcloudContainerManagerError.commandFailed(command: command, result: result)
        }

        return result
    }

    ///
    /// Reads the status an exec instance exited with.
    ///
    /// The output stream of an attached command closes when the command exits, but the exec instance is not necessarily marked as finished by the time the last byte arrives, so it is polled briefly rather than read once. The wait is short because the command has demonstrably ended already — what is being waited for is the Docker Engine writing that down.
    ///
    /// - Parameters:
    ///     - id: The exec instance identifier.
    ///     - command: The command that was run, for reporting a status that never arrives.
    ///     - client: The Docker Engine client to use.
    ///
    /// - Returns: The status the command exited with.
    ///
    /// - Throws: ``NextcloudContainerManagerError/commandStatusUnavailable(command:)`` when the Docker Engine does not report a status for a command that has finished.
    ///
    private static func exitCode(ofExec id: String, running command: [String], using client: DockerEngineClient) async throws -> Int {
        let deadline = Date().addingTimeInterval(5)

        while true {
            // Each request carries what is left of the allowance rather than the transport's own default, because a deadline that only bounds the loop is no deadline at all: one request left unbounded would let a silent Docker Engine hold this call for the length of the default instead, which is precisely the shape of the defect this wait was rewritten to remove.
            let remaining = deadline.timeIntervalSinceNow

            guard remaining > 0 else {
                throw NextcloudContainerManagerError.commandStatusUnavailable(command: command)
            }

            let response: EngineResponse

            do {
                response = try await client.get(path: "/exec/\(id)/json", timeout: max(0.001, remaining))
            } catch NextcloudContainerManagerError.engineRequestTimedOut {
                throw NextcloudContainerManagerError.commandStatusUnavailable(command: command)
            }

            // The exec instance disappears together with its container, so a container removed underneath a command has to be reported as the missing resource it is rather than as an undecodable response body.
            try response.checked([200])

            let info = try response.decode(ExecInspectResponse.self)

            if !info.Running {
                // A stopped exec instance always carries a status, so its absence is a malformed response rather than a zero. Reading it as zero would let an incomplete answer pass for a command that succeeded, which is the one direction this must never fail in.
                guard let exitCode = info.ExitCode else {
                    throw NextcloudContainerManagerError.commandStatusUnavailable(command: command)
                }

                return exitCode
            }

            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
