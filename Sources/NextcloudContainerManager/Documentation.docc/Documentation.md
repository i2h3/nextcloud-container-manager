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

// Provision the fixtures your tests need, keyed by the container id.
try await NextcloudContainerManager.addUser("alice", inContainer: container.id)

// Tear everything down — stopping the container discards all of its data.
try await NextcloudContainerManager.delete(container.id)
```

### Managing the server

``NextcloudContainerManager/deploy(configuration:)`` returns a ``NextcloudContainer`` — a lightweight value carrying the container's ``NextcloudContainer/id`` and the host ``NextcloudContainer/port`` the server is reachable on.

Every management operation is a stateless function on ``NextcloudContainerManager`` keyed by the container identifier, so callers that only persist an id — for example a Model Context Protocol server — can use them without holding the ``NextcloudContainer`` value.
Use ``NextcloudContainerManager/addApp(_:inContainer:)``, ``NextcloudContainerManager/removeApp(_:inContainer:)``, ``NextcloudContainerManager/enableApp(_:inContainer:)`` and ``NextcloudContainerManager/disableApp(_:inContainer:)`` for apps, and ``NextcloudContainerManager/addUser(_:inContainer:)``, ``NextcloudContainerManager/removeUser(_:inContainer:)``, ``NextcloudContainerManager/enableUser(_:inContainer:)`` and ``NextcloudContainerManager/disableUser(_:inContainer:)`` for users.
Each maps to an `occ` command executed inside the container, so a failure surfaces as a thrown error rather than a silent no-op.

### High Performance Backend for Files

Set ``NextcloudConfiguration/pushNotifications`` to `true` to enable the High Performance Backend so connected clients receive websocket push notifications instead of polling.

```swift
let container = try await NextcloudContainerManager.deploy(
    configuration: NextcloudConfiguration(pushNotifications: true)
)

// The websocket push endpoint is reachable at http://localhost:<pushPort>.
print("Push endpoint on port \(container.pushPort!)")
```

The `notify_push` app requires a Redis server, so the deployment additionally spins up a Redis sidecar on a dedicated network, configures the Nextcloud instance to use it, installs the app, launches its push daemon inside the container and registers it with the server.
The host port the endpoint is reachable on is reported as ``NextcloudContainer/pushPort``, and clients discover it automatically through the Nextcloud capabilities API.
``NextcloudContainerManager/delete(_:)`` removes the sidecar and network along with the container.

## Topics

### Essentials

- ``NextcloudContainerManager``
- ``NextcloudConfiguration``

### Working with a running container

- ``NextcloudContainer``

### Errors

- ``NextcloudContainerManagerError``
