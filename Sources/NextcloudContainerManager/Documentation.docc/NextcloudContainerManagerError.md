# ``NextcloudContainerManagerError``

## Topics

### Reaching Docker

- ``dockerDesktopNotFound``
- ``dockerDesktopLaunchFailed``
- ``dockerEngineUnavailable(socketPath:)``

### Docker Engine requests

- ``engineRequestFailed(path:statusCode:message:)``
- ``engineRequestTimedOut(path:)``
- ``engineResponseUnreadable(path:)``
- ``imagePullFailed(image:message:)``

### Naming and ports

- ``invalidContainerName(_:)``
- ``containerNameUnavailable(_:)``
- ``portUnavailable(_:)``
- ``couldNotAllocatePort``

### Running commands

- ``commandFailed(command:result:)``
- ``commandTimedOut(command:)``
- ``commandStatusUnavailable(command:)``

### Waiting for a server

- ``nextcloudInstallationTimedOut``
- ``pushBackendTimedOut``
- ``unsupportedArchitecture(_:)``
