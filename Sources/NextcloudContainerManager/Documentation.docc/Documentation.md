# ``NextcloudContainerManager``

Control the local deployment of ephemeral Nextcloud Docker containers programmatically from Swift.

## Overview

`NextcloudContainerManager` talks to the [Docker Engine API](https://docs.docker.com/reference/api/engine/) on macOS to spin up throwaway Nextcloud servers.
It is built for developers of native Nextcloud client apps who want to run automated tests against a real instance instead of a mock, including full end-to-end tests.

A single call deploys a container, waits until the Nextcloud instance reports itself ready, and forwards it to a free port on the host.
The instance comes up backed by a SQLite database with the administrator account `admin` / `admin`.
Containers are created with Docker's auto-remove flag, so stopping one is enough to discard all of its data.

### Requirements

- macOS with [Docker Desktop](https://www.docker.com/products/docker-desktop/) installed. When Docker is not running, ``NextcloudContainerManager`` launches it automatically and waits for the engine to become available.
- A Swift 6.3 toolchain.

### Deploying a container

```swift
import NextcloudContainerManager

// Deploy an ephemeral Nextcloud server with the first-run wizard disabled.
let container = try await NextcloudContainerManager.deploy(
    configuration: NextcloudConfiguration(disabledApps: ["firstrunwizard"])
)

// The instance is live now; log in as `admin` / `admin` or hit its HTTP port directly.
print("Nextcloud is ready at http://localhost:\(container.port)")

// Provision the fixtures your tests need.
try await container.addUser("alice")

// Tear everything down — stopping the container discards all of its data.
try await container.delete()
```

### Managing the server

Once a container is running you manage its apps and users through ``NextcloudContainer``.
Use ``NextcloudContainer/addApp(_:)``, ``NextcloudContainer/removeApp(_:)``, ``NextcloudContainer/enableApp(_:)`` and ``NextcloudContainer/disableApp(_:)`` for apps, and ``NextcloudContainer/addUser(_:)``, ``NextcloudContainer/removeUser(_:)``, ``NextcloudContainer/enableUser(_:)`` and ``NextcloudContainer/disableUser(_:)`` for users.
Every one of these maps to an `occ` command executed inside the container, so a failure surfaces as a thrown error rather than a silent no-op.

## Topics

### Essentials

- ``NextcloudContainerManager``
- ``NextcloudConfiguration``

### Working with a running container

- ``NextcloudContainer``

### Errors

- ``NextcloudContainerManagerError``
