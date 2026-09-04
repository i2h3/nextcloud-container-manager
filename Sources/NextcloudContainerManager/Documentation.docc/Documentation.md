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

``NextcloudContainerManager/deploy(configuration:)`` returns a ``NextcloudContainer`` — a lightweight value carrying the container's ``NextcloudContainer/id``, its ``NextcloudContainer/name`` and the host ``NextcloudContainer/port`` the server is reachable on.

Every management operation is a stateless function on ``NextcloudContainerManager`` keyed by the container identifier, so callers that only persist an id — for example a Model Context Protocol server — can use them without holding the ``NextcloudContainer`` value.
Use ``NextcloudContainerManager/addApp(_:timeout:inContainer:)``, ``NextcloudContainerManager/removeApp(_:timeout:inContainer:)``, ``NextcloudContainerManager/enableApp(_:timeout:inContainer:)`` and ``NextcloudContainerManager/disableApp(_:timeout:inContainer:)`` for apps, and ``NextcloudContainerManager/addUser(_:timeout:inContainer:)``, ``NextcloudContainerManager/removeUser(_:timeout:inContainer:)``, ``NextcloudContainerManager/enableUser(_:timeout:inContainer:)`` and ``NextcloudContainerManager/disableUser(_:timeout:inContainer:)`` for users.
Each maps to an `occ` command executed inside the container, so a failure surfaces as a thrown error rather than a silent no-op.

Each of them also takes a `timeout` bounding how long the command is waited on, defaulting to ``NextcloudContainerManager/defaultCommandTimeout``.
``NextcloudContainerManager/addApp(_:timeout:inContainer:)`` is the exception and defaults to the far longer ``NextcloudContainerManager/defaultAppInstallationTimeout``, because installing an app is the one command here that reaches the network: it fetches the app store's catalogue and then downloads and verifies the app archive, so how long it takes is a property of the connection rather than of `occ`.
Passing `nil` waits for as long as the command takes while still checking its exit code, which is the honest option when the duration cannot be predicted at all.
Whatever the allowance, the command is always inspected at least once, so one that has already finished is never reported as timed out.

When a test fails, ``NextcloudContainerManager/logFile(inContainer:)`` copies the Nextcloud application log (`data/nextcloud.log`) out of the container into a temporary file and returns its URL — a point-in-time snapshot the same id-only callers can read.
``NextcloudContainerManager/accessLogFile(inContainer:)`` does the same for the Apache access log, which records one line per handled request and therefore shows what a failing client actually sent and which status code it was answered with.
``NextcloudContainerManager/errorLogFile(inContainer:)`` returns the Apache error log next to it, holding what the web server itself reports — startup notices and the failures of requests that died before Nextcloud could log anything about them.
Inside the container both are symbolic links to the standard output and standard error of the container rather than files, so they are read from its output streams, the same source as `docker logs`.
Mind that these two trail the container: the Docker Engine hands out what it has captured, and an idle container was observed to withhold its last lines for more than a minute, so read them after the exercise they should cover has run rather than right after a single request.

### Pinning the name and the port

A deployment normally takes whatever host port happens to be free and lets the Docker Engine generate a container name, which is right for a throwaway container.
Sometimes it is necessary to have a stable port or container name, though.
Set ``NextcloudConfiguration/name`` and ``NextcloudConfiguration/port`` to keep both stable across runs.

```swift
let container = try await NextcloudContainerManager.deploy(
    configuration: NextcloudConfiguration(name: "nextcloud-tests", port: 8080)
)
```

Both are checked before anything is created, so a taken port fails with ``NextcloudContainerManagerError/portUnavailable(_:)``, a taken name with ``NextcloudContainerManagerError/containerNameUnavailable(_:)`` and a name the Docker Engine would not accept with ``NextcloudContainerManagerError/invalidContainerName(_:)``.
A pinned name doubles as an identifier: every function keyed by ``NextcloudContainer/id`` takes it in place of the identifier, so a leftover container can be torn down with ``NextcloudContainerManager/delete(_:)`` without having persisted its identifier.
The name a deployment ended up with is reported as ``NextcloudContainer/name`` in either case, so a container which was left to the Docker Engine to name can be recognized in `docker ps` too.

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
