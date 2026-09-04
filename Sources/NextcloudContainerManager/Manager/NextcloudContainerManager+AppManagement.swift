// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// App management for ``NextcloudContainerManager``.
///
/// These functions wrap the `occ app:*` commands run as `www-data` inside the container. They live in a dedicated file to keep the app-management concern separate from the core container lifecycle in ``NextcloudContainerManager``.
///
public extension NextcloudContainerManager {
    ///
    /// How long ``addApp(_:timeout:inContainer:)`` waits for an installation by default before it is reported as timed out.
    ///
    /// Installing an app is the one command in this package that reaches the network: `occ app:install` fetches the app store's catalogue, then downloads and verifies the app archive, so its duration is dominated by the download and not by `occ` itself. It is given an allowance an order of magnitude above ``defaultCommandTimeout`` for that reason, which covers a large app over a slow link while still bounding a stalled download rather than waiting on it forever. Pass an explicit `timeout` to widen or narrow it, or `nil` to wait for as long as the download takes.
    ///
    static let defaultAppInstallationTimeout: TimeInterval = 300

    ///
    /// Installs a Nextcloud app by executing `occ app:install` in the container with the given identifier.
    ///
    /// This is the path taken for every app in ``NextcloudConfiguration/enabledApps`` that the image does not ship already, and for the `notify_push` app when ``NextcloudConfiguration/pushNotifications`` is enabled. All of them are app-store downloads and are given ``defaultAppInstallationTimeout`` rather than ``defaultCommandTimeout`` because of it.
    ///
    /// - Parameters:
    ///     - app: The app identifier expected by the `occ` command line.
    ///     - timeout: How long to wait for the installation to finish, or `nil` to wait for as long as it takes. Defaults to ``defaultAppInstallationTimeout``.
    ///     - id: The Docker container identifier to run the command in.
    ///
    /// - Throws: ``NextcloudContainerManagerError/commandFailed(command:result:)`` if the command exits with a non-zero status, ``NextcloudContainerManagerError/commandTimedOut(command:)`` if it produces nothing within `timeout`, ``NextcloudContainerManagerError/commandStatusUnavailable(command:)`` if it finishes without the Docker Engine reporting a status, `CancellationError` if the surrounding task is cancelled while waiting, or another case of ``NextcloudContainerManagerError`` for a Docker Engine request that fails, times out or cannot be made.
    ///
    static func addApp(_ app: String, timeout: TimeInterval? = defaultAppInstallationTimeout, inContainer id: String) async throws {
        try await runOCC(["app:install", app], timeout: timeout, inContainer: id)
    }

    ///
    /// Removes a Nextcloud app by executing `occ app:remove` in the container with the given identifier.
    ///
    /// - Parameters:
    ///     - app: The app identifier expected by the `occ` command line.
    ///     - timeout: How long to wait for the command to finish, or `nil` to wait for as long as it takes. Defaults to ``defaultCommandTimeout``.
    ///     - id: The Docker container identifier to run the command in.
    ///
    /// - Throws: ``NextcloudContainerManagerError/commandFailed(command:result:)`` if the command exits with a non-zero status, ``NextcloudContainerManagerError/commandTimedOut(command:)`` if it produces nothing within `timeout`, ``NextcloudContainerManagerError/commandStatusUnavailable(command:)`` if it finishes without the Docker Engine reporting a status, `CancellationError` if the surrounding task is cancelled while waiting, or another case of ``NextcloudContainerManagerError`` for a Docker Engine request that fails, times out or cannot be made.
    ///
    static func removeApp(_ app: String, timeout: TimeInterval? = defaultCommandTimeout, inContainer id: String) async throws {
        try await runOCC(["app:remove", app], timeout: timeout, inContainer: id)
    }

    ///
    /// Enables a Nextcloud app by executing `occ app:enable` in the container with the given identifier.
    ///
    /// - Parameters:
    ///     - app: The app identifier expected by the `occ` command line.
    ///     - timeout: How long to wait for the command to finish, or `nil` to wait for as long as it takes. Defaults to ``defaultCommandTimeout``.
    ///     - id: The Docker container identifier to run the command in.
    ///
    /// - Throws: ``NextcloudContainerManagerError/commandFailed(command:result:)`` if the command exits with a non-zero status, ``NextcloudContainerManagerError/commandTimedOut(command:)`` if it produces nothing within `timeout`, ``NextcloudContainerManagerError/commandStatusUnavailable(command:)`` if it finishes without the Docker Engine reporting a status, `CancellationError` if the surrounding task is cancelled while waiting, or another case of ``NextcloudContainerManagerError`` for a Docker Engine request that fails, times out or cannot be made.
    ///
    static func enableApp(_ app: String, timeout: TimeInterval? = defaultCommandTimeout, inContainer id: String) async throws {
        try await runOCC(["app:enable", app], timeout: timeout, inContainer: id)
    }

    ///
    /// Disables a Nextcloud app by executing `occ app:disable` in the container with the given identifier.
    ///
    /// - Parameters:
    ///     - app: The app identifier expected by the `occ` command line.
    ///     - timeout: How long to wait for the command to finish, or `nil` to wait for as long as it takes. Defaults to ``defaultCommandTimeout``.
    ///     - id: The Docker container identifier to run the command in.
    ///
    /// - Throws: ``NextcloudContainerManagerError/commandFailed(command:result:)`` if the command exits with a non-zero status, ``NextcloudContainerManagerError/commandTimedOut(command:)`` if it produces nothing within `timeout`, ``NextcloudContainerManagerError/commandStatusUnavailable(command:)`` if it finishes without the Docker Engine reporting a status, `CancellationError` if the surrounding task is cancelled while waiting, or another case of ``NextcloudContainerManagerError`` for a Docker Engine request that fails, times out or cannot be made.
    ///
    static func disableApp(_ app: String, timeout: TimeInterval? = defaultCommandTimeout, inContainer id: String) async throws {
        try await runOCC(["app:disable", app], timeout: timeout, inContainer: id)
    }
}
