// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

///
/// User management for ``NextcloudContainerManager``.
///
/// These functions wrap the `occ user:*` commands run as `www-data` inside the container. They live in a dedicated file to keep the user-management concern separate from the core container lifecycle in ``NextcloudContainerManager``.
///
public extension NextcloudContainerManager {
    ///
    /// Adds a Nextcloud user by executing `occ user:add` in the container with the given identifier.
    ///
    /// The user identifier is reused as the account password, which is safe for the local, throwaway test environments this package targets. The password is passed via the `OC_PASS` environment variable and the `--password-from-env` flag so that `occ` runs non-interactively.
    ///
    /// - Parameters:
    ///     - user: The user identifier expected by the `occ` command line.
    ///     - id: The Docker container identifier to run the command in.
    ///
    /// - Throws: A `DockerClientError` if the command cannot be run or exits with a non-zero status.
    ///
    static func addUser(_ user: String, inContainer id: String) async throws {
        try await runOCC(["user:add", "--password-from-env", user], environment: ["OC_PASS=\(user)"], inContainer: id)
    }

    ///
    /// Removes a Nextcloud user by executing `occ user:delete` in the container with the given identifier.
    ///
    /// - Parameters:
    ///     - user: The user identifier expected by the `occ` command line.
    ///     - id: The Docker container identifier to run the command in.
    ///
    /// - Throws: A `DockerClientError` if the command cannot be run or exits with a non-zero status.
    ///
    static func removeUser(_ user: String, inContainer id: String) async throws {
        try await runOCC(["user:delete", user], inContainer: id)
    }

    ///
    /// Enables a Nextcloud user by executing `occ user:enable` in the container with the given identifier.
    ///
    /// - Parameters:
    ///     - user: The user identifier expected by the `occ` command line.
    ///     - id: The Docker container identifier to run the command in.
    ///
    /// - Throws: A `DockerClientError` if the command cannot be run or exits with a non-zero status.
    ///
    static func enableUser(_ user: String, inContainer id: String) async throws {
        try await runOCC(["user:enable", user], inContainer: id)
    }

    ///
    /// Disables a Nextcloud user by executing `occ user:disable` in the container with the given identifier.
    ///
    /// - Parameters:
    ///     - user: The user identifier expected by the `occ` command line.
    ///     - id: The Docker container identifier to run the command in.
    ///
    /// - Throws: A `DockerClientError` if the command cannot be run or exits with a non-zero status.
    ///
    static func disableUser(_ user: String, inContainer id: String) async throws {
        try await runOCC(["user:disable", user], inContainer: id)
    }
}
