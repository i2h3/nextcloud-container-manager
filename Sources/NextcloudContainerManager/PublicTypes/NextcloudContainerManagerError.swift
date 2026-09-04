// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

///
/// Errors that can be thrown by `NextcloudContainerManager`.
///
public enum NextcloudContainerManagerError: Error {
    ///
    /// Docker Desktop was not found at its expected path (`/Applications/Docker.app`).
    ///
    case dockerDesktopNotFound

    ///
    /// Docker Desktop was found but could not be launched.
    ///
    case dockerDesktopLaunchFailed

    ///
    /// A container of the name requested through ``NextcloudConfiguration/name`` exists already.
    ///
    /// The associated value is the requested name. Names are taken by stopped containers too, so a leftover deployment which has not been removed yet occupies the name as well.
    ///
    case containerNameUnavailable(String)

    ///
    /// The name requested through ``NextcloudConfiguration/name`` is not one the Docker Engine accepts.
    ///
    /// The associated value is the requested name. The Docker Engine restricts container names to `[a-zA-Z0-9][a-zA-Z0-9_.-]+`.
    ///
    case invalidContainerName(String)

    ///
    /// A host port requested through ``NextcloudConfiguration/port`` or ``NextcloudConfiguration/pushPort`` is already in use.
    ///
    /// The associated value is the requested port.
    ///
    case portUnavailable(UInt16)

    ///
    /// A command run inside a container exited with a non-zero status.
    ///
    /// The associated values are the command as it was run and what it produced. Read ``CommandResult/standardError`` of the result to learn why it refused: `occ` reports its reasons there, and a message such as a rejected password or an unknown app identifier explains a failure that the status alone would leave a caller guessing about.
    ///
    case commandFailed(command: [String], result: CommandResult)

    ///
    /// A command run inside a container produced nothing for longer than it was given.
    ///
    /// The associated value is the command as it was run. The command itself is not stopped by this — an exec instance outlives the request that started it — so a container that is still around may well finish it afterwards.
    ///
    case commandTimedOut(command: [String])

    ///
    /// The Docker Engine reported an architecture the `notify_push` app ships no binary for, so the High Performance Backend cannot be started.
    ///
    /// The associated value is the reported architecture.
    ///
    case unsupportedArchitecture(String)
}
