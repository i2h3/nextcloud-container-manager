// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

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
    ///     - timeout: How long to wait for the command to finish, or `nil` to wait for as long as it takes. Defaults to ``defaultCommandTimeout``.
    ///     - id: The Docker container identifier to run the command in.
    ///
    /// - Throws: ``NextcloudContainerManagerError/commandFailed(command:result:)`` if the command exits with a non-zero status, ``NextcloudContainerManagerError/commandTimedOut(command:)`` if it produces nothing within `timeout`, `CancellationError` if the surrounding task is cancelled while waiting, or a `DockerClientError` for any API-level failure.
    ///
    static func addUser(_ user: String, timeout: TimeInterval? = defaultCommandTimeout, inContainer id: String) async throws {
        try await runOCC(["user:add", "--password-from-env", user], environment: ["OC_PASS=\(user)"], timeout: timeout, inContainer: id)
    }

    ///
    /// Removes a Nextcloud user by executing `occ user:delete` in the container with the given identifier.
    ///
    /// - Parameters:
    ///     - user: The user identifier expected by the `occ` command line.
    ///     - timeout: How long to wait for the command to finish, or `nil` to wait for as long as it takes. Defaults to ``defaultCommandTimeout``.
    ///     - id: The Docker container identifier to run the command in.
    ///
    /// - Throws: ``NextcloudContainerManagerError/commandFailed(command:result:)`` if the command exits with a non-zero status, ``NextcloudContainerManagerError/commandTimedOut(command:)`` if it produces nothing within `timeout`, `CancellationError` if the surrounding task is cancelled while waiting, or a `DockerClientError` for any API-level failure.
    ///
    static func removeUser(_ user: String, timeout: TimeInterval? = defaultCommandTimeout, inContainer id: String) async throws {
        try await runOCC(["user:delete", user], timeout: timeout, inContainer: id)
    }

    ///
    /// Enables a Nextcloud user by executing `occ user:enable` in the container with the given identifier.
    ///
    /// - Parameters:
    ///     - user: The user identifier expected by the `occ` command line.
    ///     - timeout: How long to wait for the command to finish, or `nil` to wait for as long as it takes. Defaults to ``defaultCommandTimeout``.
    ///     - id: The Docker container identifier to run the command in.
    ///
    /// - Throws: ``NextcloudContainerManagerError/commandFailed(command:result:)`` if the command exits with a non-zero status, ``NextcloudContainerManagerError/commandTimedOut(command:)`` if it produces nothing within `timeout`, `CancellationError` if the surrounding task is cancelled while waiting, or a `DockerClientError` for any API-level failure.
    ///
    static func enableUser(_ user: String, timeout: TimeInterval? = defaultCommandTimeout, inContainer id: String) async throws {
        try await runOCC(["user:enable", user], timeout: timeout, inContainer: id)
    }

    ///
    /// Disables a Nextcloud user by executing `occ user:disable` in the container with the given identifier.
    ///
    /// - Parameters:
    ///     - user: The user identifier expected by the `occ` command line.
    ///     - timeout: How long to wait for the command to finish, or `nil` to wait for as long as it takes. Defaults to ``defaultCommandTimeout``.
    ///     - id: The Docker container identifier to run the command in.
    ///
    /// - Throws: ``NextcloudContainerManagerError/commandFailed(command:result:)`` if the command exits with a non-zero status, ``NextcloudContainerManagerError/commandTimedOut(command:)`` if it produces nothing within `timeout`, `CancellationError` if the surrounding task is cancelled while waiting, or a `DockerClientError` for any API-level failure.
    ///
    static func disableUser(_ user: String, timeout: TimeInterval? = defaultCommandTimeout, inContainer id: String) async throws {
        try await runOCC(["user:disable", user], timeout: timeout, inContainer: id)
    }
}
