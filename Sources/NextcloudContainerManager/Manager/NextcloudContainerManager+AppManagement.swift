// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

///
/// App management for ``NextcloudContainerManager``.
///
/// These functions wrap the `occ app:*` commands run as `www-data` inside the container. They live in a dedicated file to keep the app-management concern separate from the core container lifecycle in ``NextcloudContainerManager``.
///
public extension NextcloudContainerManager {
    ///
    /// Installs a Nextcloud app by executing `occ app:install` in the container with the given identifier.
    ///
    /// - Parameters:
    ///     - app: The app identifier expected by the `occ` command line.
    ///     - id: The Docker container identifier to run the command in.
    ///
    /// - Throws: A `DockerClientError` if the command cannot be run or exits with a non-zero status.
    ///
    static func addApp(_ app: String, inContainer id: String) async throws {
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
    static func removeApp(_ app: String, inContainer id: String) async throws {
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
    static func enableApp(_ app: String, inContainer id: String) async throws {
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
    static func disableApp(_ app: String, inContainer id: String) async throws {
        try await runOCC(["app:disable", app], inContainer: id)
    }
}
