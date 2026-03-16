import Foundation
import NextcloudContainerManager

/// Parse an optional --tag <value> argument, e.g.: swift run Runner --tag 30
let tag: String = {
    let args = CommandLine.arguments
    if let idx = args.firstIndex(of: "--tag"), idx + 1 < args.count {
        return args[idx + 1]
    }
    return "latest"
}()

/// Task.detached avoids inheriting the @MainActor isolation of top-level
/// main.swift code, keeping the cooperative thread pool free while we block
/// on readLine() below.
let semaphore = DispatchSemaphore(value: 0)

Task.detached {
    defer { semaphore.signal() }
    do {
        print("Deploying nextcloud:\(tag)…")
        let container = try await NextcloudContainerManager.deploy(
            configuration: NextcloudConfiguration(
                tag: tag,
                disabledApps: [
                    "bruteforcesettings",
                    "firstrunwizard",
                    "nextcloud_announcements",
                    "password_policy",
                ]
            )
        )
        print("Container ready")
        print("  ID:  \(container.id.prefix(12))")
        print("  URL: http://localhost:\(container.port)")
        print("\nPress Enter to stop and remove the container…")
        _ = readLine()
        print("Stopping…")
        try await container.delete()
        print("Done.")
    } catch {
        print("Error: \(error)")
        exit(1)
    }
}

semaphore.wait()
