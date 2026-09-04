// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Every failure this package reports.
///
/// One type covers the whole library. A caller does not have to know which internal layer a failure came from, and there is no second error type to catch alongside this one: anything else that escapes came from the standard library or Foundation — `CancellationError` while waiting on a command, or an error raised while writing a log snapshot to disk — and is named at the function where it can occur.
///
/// Cases whose names begin with `engine` describe the Docker Engine's answer to a request the library made on the caller's behalf, and carry the request path so that the failure says what was being asked for. The rest describe the caller's own deployment: a name or port that cannot be had, a command that refused, a server that never became ready.
///
public enum NextcloudContainerManagerError: Error, Equatable, LocalizedError {
    ///
    /// Docker Desktop was not found at its expected path (`/Applications/Docker.app`).
    ///
    case dockerDesktopNotFound

    ///
    /// Docker Desktop was found but could not be launched.
    ///
    case dockerDesktopLaunchFailed

    ///
    /// The Docker Engine socket was not there, so no request could be made at all.
    ///
    /// The associated value is the socket path. This is distinct from ``dockerDesktopNotFound``: Docker Desktop is installed, and was launched successfully if it was not already running, but its socket never appeared. A caller can act on the difference — one is a missing installation, the other a Docker that is not finishing its start.
    ///
    case dockerEngineUnavailable(socketPath: String)

    ///
    /// The Docker Engine refused a request.
    ///
    /// The associated values are the request path, the status code, and the Docker Engine's own explanation. The message is where the reason lives: a container that does not exist, a name already taken, a port already published.
    ///
    case engineRequestFailed(path: String, statusCode: Int, message: String)

    ///
    /// The Docker Engine accepted a request and then went quiet for longer than the request allowed.
    ///
    /// The associated value is the request path. This is what a stalled daemon looks like from here — the socket stays open with nothing arriving on it — and it is what bounds a call that would otherwise wait forever.
    ///
    case engineRequestTimedOut(path: String)

    ///
    /// The Docker Engine answered in a shape this package could not read.
    ///
    /// The associated value is the request path. This is a malformed HTTP response or an archive that is not the tar stream the endpoint promises, rather than a request that was refused — a refusal is ``engineRequestFailed(path:statusCode:message:)``.
    ///
    case engineResponseUnreadable(path: String)

    ///
    /// Pulling an image from its registry failed.
    ///
    /// The associated values are the image reference and the error the Docker Engine reported inside the pull stream, which is where a pull failure is reported rather than in the HTTP status.
    ///
    case imagePullFailed(image: String, message: String)

    ///
    /// The kernel would not hand out a port to publish the server on.
    ///
    /// This is the host running out of sockets or descriptors rather than a port being taken, so there is no port number to report and nothing for the caller to choose differently. A port the caller asked for and cannot have is ``portUnavailable(_:)``.
    ///
    case couldNotAllocatePort

    ///
    /// A host port requested through ``NextcloudConfiguration/port`` or ``NextcloudConfiguration/pushPort`` is already in use.
    ///
    /// The associated value is the requested port.
    ///
    case portUnavailable(UInt16)

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
    /// A command run inside a container exited with a non-zero status.
    ///
    /// The associated values are the command as it was run and what it produced. Read ``CommandResult/standardError`` of the result to learn why it refused: `occ` reports its reasons there, and a message such as a rejected password or an unknown app identifier explains a failure that the status alone would leave a caller guessing about.
    ///
    case commandFailed(command: [String], result: CommandResult)

    ///
    /// A command run inside a container produced nothing for longer than it was given.
    ///
    /// The associated value is the command as it was run. Nothing is undone by this: the deadline can expire before the Docker Engine was even asked to start the command, in which case it never ran, and otherwise the command keeps running, because an exec instance outlives the request that started it. So a container that is still around may well finish it afterwards.
    ///
    case commandTimedOut(command: [String])

    ///
    /// A command finished, but the Docker Engine never reported what it exited with.
    ///
    /// The associated value is the command as it was run. The command itself is done — its output was collected in full — so this is the Docker Engine failing to write down a status rather than the command failing to produce one, and the output it did produce is lost with the status. It is distinct from ``commandTimedOut(command:)``, where the command had not finished.
    ///
    case commandStatusUnavailable(command: [String])

    ///
    /// The Nextcloud instance never finished installing itself.
    ///
    /// A freshly deployed container runs its installer before it serves anything, and this is that never completing within the time ``NextcloudContainerManager/deploy(configuration:)`` allows for it. The container itself started, so it is still there to be inspected — its logs are reachable through ``NextcloudContainerManager/logFile(inContainer:)``.
    ///
    case nextcloudInstallationTimedOut

    ///
    /// The push daemon never began answering on its endpoint.
    ///
    /// Only reachable when ``NextcloudConfiguration/pushNotifications`` is enabled. The daemon was launched inside the container and did not report itself ready, so the High Performance Backend cannot be registered with the server.
    ///
    case pushBackendTimedOut

    ///
    /// The Docker Engine reported an architecture the `notify_push` app ships no binary for, so the High Performance Backend cannot be started.
    ///
    /// The associated value is the reported architecture.
    ///
    case unsupportedArchitecture(String)

    ///
    /// A sentence describing the failure, for reporting it to a person.
    ///
    /// This is what `localizedDescription` returns, so a failure printed by a test harness reads as an explanation rather than as the name of an enum case.
    ///
    public var errorDescription: String? {
        switch self {
            case .dockerDesktopNotFound:
                "Docker Desktop is not installed at /Applications/Docker.app."
            case .dockerDesktopLaunchFailed:
                "Docker Desktop is installed but could not be launched."
            case let .dockerEngineUnavailable(socketPath):
                "The Docker Engine socket at \(socketPath) is not there, so the Docker Engine cannot be reached."
            case let .engineRequestFailed(path, statusCode, message):
                "The Docker Engine answered \(statusCode) to \(path): \(message)"
            case let .engineRequestTimedOut(path):
                "The Docker Engine stopped answering \(path) before the request was allowed to give up."
            case let .engineResponseUnreadable(path):
                "The Docker Engine answered \(path) in a shape this package could not read."
            case let .imagePullFailed(image, message):
                "Pulling the image \(image) failed: \(message)"
            case .couldNotAllocatePort:
                "The kernel would not hand out a port to publish the server on."
            case let .portUnavailable(port):
                "The host port \(port) is already in use."
            case let .containerNameUnavailable(name):
                "A container named \(name) exists already."
            case let .invalidContainerName(name):
                "The Docker Engine does not accept \(name) as a container name."
            case let .commandFailed(command, result):
                "The command \(command.joined(separator: " ")) exited with status \(result.exitCode): \(result.standardError.isEmpty ? result.standardOutput : result.standardError)"
            case let .commandTimedOut(command):
                "The command \(command.joined(separator: " ")) produced nothing for longer than it was given."
            case let .commandStatusUnavailable(command):
                "The command \(command.joined(separator: " ")) finished, but the Docker Engine never reported what it exited with."
            case .nextcloudInstallationTimedOut:
                "The Nextcloud instance never finished installing itself."
            case .pushBackendTimedOut:
                "The push daemon never began answering on its endpoint."
            case let .unsupportedArchitecture(architecture):
                "The notify_push app ships no binary for the \(architecture) architecture."
        }
    }
}
