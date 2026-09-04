# ``NextcloudContainerManager-swift.enum``

## Topics

### Managing the container lifecycle

- ``deploy(configuration:)``
- ``delete(_:)``

### Managing apps

- ``addApp(_:timeout:inContainer:)``
- ``removeApp(_:timeout:inContainer:)``
- ``enableApp(_:timeout:inContainer:)``
- ``disableApp(_:timeout:inContainer:)``

### Managing users

- ``addUser(_:timeout:inContainer:)``
- ``removeUser(_:timeout:inContainer:)``
- ``enableUser(_:timeout:inContainer:)``
- ``disableUser(_:timeout:inContainer:)``

### Reading logs

- ``logFile(inContainer:)``
- ``accessLogFile(inContainer:)``
- ``errorLogFile(inContainer:)``

### Bounding how long a command is waited on

- ``defaultCommandTimeout``
- ``defaultAppInstallationTimeout``
