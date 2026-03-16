import Foundation

///
/// The interface of an individual test container deployment representation.
///
public struct NextcloudContainer: Identifiable {
    ///
    /// The initial configuration this container was created with.
    ///
    public let configuration: NextcloudConfiguration

    ///
    /// The unique Docker container identifier.
    ///
    public let id: String

    ///
    /// The host port mapped to the container's HTTP port 80.
    ///
    public let port: UInt

    /// The Docker Engine client used to communicate with the daemon.
    let client: DockerEngineClient

    ///
    /// Stops the container and deletes all associated data.
    ///
    /// Because the container was created with `AutoRemove`, stopping it is
    /// sufficient — Docker removes it automatically once it exits.
    ///
    public func delete() async throws {
        // Acceptable status codes:
        //   204 – successfully stopped
        //   304 – container was already stopped (already auto-removed)
        //   404 – container no longer exists (already removed)
        let response = try await client.post(path: "/containers/\(id)/stop")
        guard [204, 304, 404].contains(response.statusCode) else {
            let message = String(data: response.body, encoding: .utf8) ?? "<no body>"
            throw DockerClientError.unexpectedStatusCode(response.statusCode, message)
        }
    }

    // MARK: - Provisioning

    ///
    /// Runs all post-deployment provisioning steps defined in the configuration.
    ///
    /// Currently this waits for the Nextcloud instance to finish its initial
    /// installation and then disables the apps listed in
    /// ``NextcloudConfiguration/disabledApps``.
    ///
    func provision() async throws {
        guard !configuration.disabledApps.isEmpty else { return }

        try await waitUntilReady()

        for app in configuration.disabledApps {
            await disableApp(app)
        }
    }

    // MARK: - Status polling

    ///
    /// Polls the Nextcloud `status.php` endpoint until the instance reports
    /// itself as installed, or a timeout is reached.
    ///
    /// - Throws: ``DockerClientError/timeout`` when the instance does not
    ///   become ready within 120 seconds.
    ///
    private func waitUntilReady() async throws {
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
            try await Task.sleep(for: .seconds(2))
        }

        throw DockerClientError.timeout
    }

    // MARK: - App management

    ///
    /// Disables a single Nextcloud app by executing `occ app:disable` inside
    /// the container.
    ///
    /// Failures are intentionally not propagated so that one broken app does
    /// not interrupt the remaining provisioning steps.
    ///
    private func disableApp(_ app: String) async {
        do {
            // 1. Create the exec instance.
            let createRequest = CreateExecRequest(
                Cmd: ["php", "occ", "app:disable", app],
                User: "www-data",
                WorkingDir: "/var/www/html"
            )
            let createResponse = try await client.post(
                path: "/containers/\(id)/exec",
                body: createRequest
            )
            guard createResponse.statusCode == 201 else { return }
            let created = try JSONDecoder().decode(
                CreateExecResponse.self,
                from: createResponse.body
            )

            // 2. Start the exec instance in detached mode.
            let startRequest = StartExecRequest(Detach: true)
            let startResponse = try await client.post(
                path: "/exec/\(created.Id)/start",
                body: startRequest
            )
            guard startResponse.statusCode == 200 else { return }

            // 3. Wait for the command to finish (up to 30 seconds).
            let execDeadline = Date().addingTimeInterval(30)
            while Date() < execDeadline {
                let inspectResponse = try await client.get(
                    path: "/exec/\(created.Id)/json"
                )
                let info = try JSONDecoder().decode(
                    ExecInspectResponse.self,
                    from: inspectResponse.body
                )
                if !info.Running { break }
                try await Task.sleep(for: .seconds(1))
            }
        } catch {
            // Intentionally ignored – see doc comment.
        }
    }
}
