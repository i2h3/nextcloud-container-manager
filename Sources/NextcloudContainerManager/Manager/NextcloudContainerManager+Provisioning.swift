// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Post-deployment provisioning for ``NextcloudContainerManager``.
///
/// These functions wait for a freshly deployed instance to become ready and then apply the steps declared in its ``NextcloudConfiguration``. They live in a dedicated file to keep the provisioning concern separate from the core container lifecycle in ``NextcloudContainerManager``.
///
extension NextcloudContainerManager {
    ///
    /// Runs all post-deployment provisioning steps defined in the container's configuration.
    ///
    /// After waiting for the Nextcloud instance to finish its initial installation, this disables the apps listed in ``NextcloudConfiguration/disabledApps``, enables the apps listed in ``NextcloudConfiguration/enabledApps`` (installing them first when necessary), creates the users listed in ``NextcloudConfiguration/users``, and finally sets up the High Performance Backend for Files when ``NextcloudConfiguration/pushNotifications`` is enabled.
    ///
    static func provision(_ container: NextcloudContainer) async throws {
        let configuration = container.configuration

        guard !configuration.disabledApps.isEmpty || !configuration.enabledApps.isEmpty || !configuration.users.isEmpty || configuration.pushNotifications else {
            return
        }

        try await waitUntilReady(port: container.port)

        for app in configuration.disabledApps {
            // A single broken app must not interrupt the remaining provisioning steps, so failures are intentionally ignored here.
            try? await disableApp(app, inContainer: container.id)
        }

        for app in configuration.enabledApps {
            // Enabling fails when the app is not present yet, in which case it is installed from the app store, which also enables it.
            do {
                try await enableApp(app, inContainer: container.id)
            } catch {
                try await addApp(app, inContainer: container.id)
            }
        }

        for user in configuration.users {
            try await addUser(user, inContainer: container.id)
        }

        if configuration.pushNotifications {
            try await setUpPushNotifications(container)
        }
    }

    ///
    /// Polls the Nextcloud `status.php` endpoint on the given host port until the instance reports itself as installed, or a timeout is reached.
    ///
    /// - Parameters:
    ///     - port: The host port the container's HTTP port 80 is mapped to.
    ///
    /// - Throws: ``DockerClientError/timeout`` when the instance does not become ready within 120 seconds.
    ///
    private static func waitUntilReady(port: UInt) async throws {
        let url = URL(string: "http://localhost:\(port)/status.php")!
        let deadline = Date().addingTimeInterval(120)

        while Date() < deadline {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let status = try JSONDecoder().decode(NextcloudStatus.self, from: data)

                if status.installed {
                    return
                }
            } catch {
                // Nextcloud is not ready yet – retry after a short delay.
            }

            try await Task.sleep(nanoseconds: 500_000_000)
        }

        throw DockerClientError.timeout
    }
}
