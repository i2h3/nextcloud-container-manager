// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Log access for ``NextcloudContainerManager``.
///
/// This function copies the Nextcloud application log out of the container so it can be inspected from the outside. It lives in a dedicated file to keep the log-access concern separate from the core container lifecycle in ``NextcloudContainerManager``.
///
public extension NextcloudContainerManager {
    ///
    /// Copies the Nextcloud application log out of the container with the given identifier and returns the URL of the extracted file.
    ///
    /// Nextcloud writes one JSON object per line to `/var/www/html/data/nextcloud.log` inside the container, capturing PHP exceptions and app-level errors. This function copies that file — which is otherwise only reachable from inside the container — to a fresh directory inside the system temporary directory using the Docker Engine archive endpoint, the same mechanism as `docker cp`. The result is a point-in-time snapshot: it reflects the log as it was when the call returned and does not update afterwards. Like the other management functions, it is keyed only by the container's ``NextcloudContainer/id`` and does not require holding the ``NextcloudContainer`` value.
    ///
    /// The caller owns the returned file and is responsible for removing it once it is no longer needed.
    ///
    /// - Parameters:
    ///     - id: The Docker container identifier to copy the log from.
    ///
    /// - Returns: The URL of the copied log file inside a unique temporary directory.
    ///
    /// - Throws: ``NextcloudContainerManagerError/dockerDesktopNotFound`` if Docker Desktop is not installed, ``NextcloudContainerManagerError/dockerDesktopLaunchFailed`` if it cannot be launched, a `DockerClientError` if the container or log file does not exist or the archive cannot be parsed, or any error raised while writing the file to disk.
    ///
    static func logFile(inContainer id: String) async throws -> URL {
        let logPath = "/var/www/html/data/nextcloud.log"

        // 1. Copy the file out of the container as a tar archive, the mechanism behind `docker cp`.
        let client = try await makeDockerEngineClient()
        let response = try await client.get(path: "/containers/\(id)/archive?path=\(logPath)")

        guard response.statusCode == 200 else {
            let message = String(data: response.body, encoding: .utf8) ?? "<no body>"
            throw DockerClientError.unexpectedStatusCode(response.statusCode, message)
        }

        // 2. Unpack the single-file archive to obtain the log's bytes as they were at call time.
        guard let contents = firstFileInTarArchive(response.body) else {
            throw DockerClientError.invalidResponse
        }

        // 3. Write the snapshot into a unique temporary directory and hand back its location.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let destination = directory.appendingPathComponent(URL(fileURLWithPath: logPath).lastPathComponent, isDirectory: false)
        try contents.write(to: destination)

        return destination
    }
}
