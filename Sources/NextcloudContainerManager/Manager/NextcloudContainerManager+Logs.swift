// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Log access for ``NextcloudContainerManager``.
///
/// These functions copy the logs of a deployment out of the container so they can be inspected from the outside, namely the Nextcloud application log written inside the container as well as the Apache access log and error log the container writes to its output streams. They live in a dedicated file to keep the log-access concern separate from the core container lifecycle in ``NextcloudContainerManager``.
///
public extension NextcloudContainerManager {
    ///
    /// Copies the Nextcloud application log out of the container with the given identifier and returns the URL of the extracted file.
    ///
    /// Nextcloud writes one JSON object per line to `/var/www/html/data/nextcloud.log` inside the container, capturing PHP exceptions and app-level errors. This function copies that file — which is otherwise only reachable from inside the container — to a fresh directory inside the system temporary directory using the Docker Engine archive endpoint, the same mechanism as `docker cp`. The result is a point-in-time snapshot: it reflects the log as it was when the call returned and does not update afterwards. Like the other management functions, it is keyed only by the container's ``NextcloudContainer/id`` and does not require holding the ``NextcloudContainer`` value.
    ///
    /// Requests the server handled are not part of this log but of the one returned by ``accessLogFile(inContainer:)``, and failures of the web server itself are reported in the one returned by ``errorLogFile(inContainer:)``.
    ///
    /// The caller owns the returned file and is responsible for removing it once it is no longer needed.
    ///
    /// - Parameters:
    ///     - id: The Docker container identifier to copy the log from.
    ///
    /// - Returns: The URL of the copied log file inside a unique temporary directory.
    ///
    /// - Throws: ``NextcloudContainerManagerError/dockerDesktopNotFound`` if Docker Desktop is not installed, ``NextcloudContainerManagerError/dockerDesktopLaunchFailed`` if it cannot be launched, ``NextcloudContainerManagerError/engineRequestFailed(path:statusCode:message:)`` if the container or log file does not exist, ``NextcloudContainerManagerError/engineResponseUnreadable(path:)`` if the archive cannot be parsed, or any error raised while writing the file to disk.
    ///
    static func logFile(inContainer id: String) async throws -> URL {
        let logPath = "/var/www/html/data/nextcloud.log"

        // 1. Copy the file out of the container as a tar archive, the mechanism behind `docker cp`.
        let client = try await makeDockerEngineClient()
        let response = try await client.get(path: "/containers/\(id)/archive?path=\(logPath)")

        try response.checked([200])

        // 2. Unpack the single-file archive to obtain the log's bytes as they were at call time.
        guard let contents = firstFileInTarArchive(response.body) else {
            throw NextcloudContainerManagerError.engineResponseUnreadable(path: response.path)
        }

        // 3. Write the snapshot into a unique temporary directory and hand back its location.
        return try writeSnapshot(contents, named: URL(fileURLWithPath: logPath).lastPathComponent)
    }

    ///
    /// Copies the Apache access log out of the container with the given identifier and returns the URL of the extracted file.
    ///
    /// The web server in front of Nextcloud logs one line per handled request in the combined log format, covering the requests a failing client made and the status codes they were answered with — which the application log in ``logFile(inContainer:)`` does not record. Inside the container `/var/log/apache2/access.log` is a symbolic link to `/dev/stdout`, so the log cannot be copied as a file and is read from the container's standard output instead, as described on ``containerStream(inContainer:standardError:)``.
    ///
    /// The result is a point-in-time snapshot: it reflects the log as it was when the call returned and does not update afterwards. It is furthermore only as complete as what the Docker Engine has captured of the container's output by that moment, and that capture trails the container by a delay which depends on whether it keeps writing. Measured against the deployments this package creates, a request showed up within about five seconds while further traffic kept arriving, whereas two requests followed by an idle container were still missing from the log after a minute of polling for them — the output evidently sits unflushed somewhere between the web server and the Docker Engine until the container writes again.
    ///
    /// Treat the log as eventually complete rather than as current: read it once the exercise it should cover has run, not right after a single request, and do not conclude from a missing line that the request never happened.
    ///
    /// Like the other management functions, it is keyed only by the container's ``NextcloudContainer/id`` and does not require holding the ``NextcloudContainer`` value.
    ///
    /// The caller owns the returned file and is responsible for removing it once it is no longer needed.
    ///
    /// - Parameters:
    ///     - id: The Docker container identifier to read the log from.
    ///
    /// - Returns: The URL of the written log file inside a unique temporary directory.
    ///
    /// - Throws: ``NextcloudContainerManagerError/dockerDesktopNotFound`` if Docker Desktop is not installed, ``NextcloudContainerManagerError/dockerDesktopLaunchFailed`` if it cannot be launched, ``NextcloudContainerManagerError/engineRequestFailed(path:statusCode:message:)`` if the container does not exist, or any error raised while writing the file to disk.
    ///
    static func accessLogFile(inContainer id: String) async throws -> URL {
        let contents = try await containerStream(inContainer: id, standardError: false)

        return try writeSnapshot(contents, named: "access.log")
    }

    ///
    /// Copies the Apache error log out of the container with the given identifier and returns the URL of the extracted file.
    ///
    /// This is what the web server itself reports rather than what Nextcloud reports: startup notices, configuration complaints and the PHP errors that never made it into the application log because the request died before Nextcloud could write one. It is therefore the log to read when a request fails without leaving a trace in ``logFile(inContainer:)``. Inside the container `/var/log/apache2/error.log` is a symbolic link to `/dev/stderr`, so it is read from the container's standard error, as described on ``containerStream(inContainer:standardError:)``.
    ///
    /// The result is a point-in-time snapshot with the same limits as the one returned by ``accessLogFile(inContainer:)``, in particular the delay described there: an idle container can withhold its most recent lines for a minute and more. It is keyed only by the container's ``NextcloudContainer/id`` just like the other management functions.
    ///
    /// The caller owns the returned file and is responsible for removing it once it is no longer needed.
    ///
    /// - Parameters:
    ///     - id: The Docker container identifier to read the log from.
    ///
    /// - Returns: The URL of the written log file inside a unique temporary directory.
    ///
    /// - Throws: ``NextcloudContainerManagerError/dockerDesktopNotFound`` if Docker Desktop is not installed, ``NextcloudContainerManagerError/dockerDesktopLaunchFailed`` if it cannot be launched, ``NextcloudContainerManagerError/engineRequestFailed(path:statusCode:message:)`` if the container does not exist, or any error raised while writing the file to disk.
    ///
    static func errorLogFile(inContainer id: String) async throws -> URL {
        let contents = try await containerStream(inContainer: id, standardError: true)

        return try writeSnapshot(contents, named: "error.log")
    }

    ///
    /// Reads one of the two output streams of a container from the Docker Engine log endpoint, the same source as `docker logs`.
    ///
    /// The endpoint answers with both streams interleaved into frames rather than with plain text, because the containers this package deploys have no pseudo-terminal attached, so the response is handed to ``demultiplexDockerStream(_:)`` and only the requested stream is returned. Asking the endpoint for the one stream alone is not enough: its frames carry headers either way.
    ///
    /// What the endpoint hands out is what the Docker Engine has captured so far, which is not necessarily everything the container has written — see ``accessLogFile(inContainer:)`` for how far behind it can be.
    ///
    /// - Parameters:
    ///     - id: The Docker container identifier to read from.
    ///     - standardError: Whether to return standard error rather than standard output.
    ///
    /// - Returns: The bytes the container wrote to the requested stream so far.
    ///
    /// - Throws: ``NextcloudContainerManagerError/dockerDesktopNotFound`` if Docker Desktop is not installed, ``NextcloudContainerManagerError/dockerDesktopLaunchFailed`` if it cannot be launched, or ``NextcloudContainerManagerError/engineRequestFailed(path:statusCode:message:)`` if the container does not exist.
    ///
    private static func containerStream(inContainer id: String, standardError: Bool) async throws -> Data {
        let client = try await makeDockerEngineClient()
        let stream = standardError ? "stderr" : "stdout"
        let response = try await client.get(path: "/containers/\(id)/logs?\(stream)=true")

        try response.checked([200])

        let streams = demultiplexDockerStream(response.body)

        return standardError ? streams.standardError : streams.standardOutput
    }

    ///
    /// Writes a log snapshot into a freshly created directory inside the system temporary directory.
    ///
    /// Each snapshot gets a directory of its own so repeated calls never overwrite one another and the caller can remove a snapshot along with its directory.
    ///
    /// - Parameters:
    ///     - contents: The bytes to write.
    ///     - name: The file name to write them under.
    ///
    /// - Returns: The URL of the written file.
    ///
    private static func writeSnapshot(_ contents: Data, named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let destination = directory.appendingPathComponent(name, isDirectory: false)
        try contents.write(to: destination)

        return destination
    }
}
