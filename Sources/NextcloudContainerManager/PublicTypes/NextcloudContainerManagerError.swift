// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

///
/// Errors that can be thrown by `NextcloudContainerManager`.
///
public enum NextcloudContainerManagerError: Error {
    ///
    /// Docker Desktop was not found at its expected path (`/Applications/Docker.app`).
    ///
    case dockerDesktopNotFound

    ///
    /// Docker Desktop was found but could not be launched.
    ///
    case dockerDesktopLaunchFailed

    ///
    /// A container of the name requested through ``NextcloudConfiguration/name`` exists already.
    ///
    /// The associated value is the requested name. Names are taken by stopped containers too, so a leftover deployment which has not been removed yet occupies the name as well.
    ///
    case containerNameUnavailable(String)

    ///
    /// The name requested through ``NextcloudConfiguration/name`` is not one the Docker Engine accepts.
    ///
    /// The associated value is the requested name. The Docker Engine restricts container names to `[a-zA-Z0-9][a-zA-Z0-9_.-]+`.
    ///
    case invalidContainerName(String)

    ///
    /// A host port requested through ``NextcloudConfiguration/port`` or ``NextcloudConfiguration/pushPort`` is already in use.
    ///
    /// The associated value is the requested port.
    ///
    case portUnavailable(UInt16)

    ///
    /// The Docker Engine reported an architecture the `notify_push` app ships no binary for, so the High Performance Backend cannot be started.
    ///
    /// The associated value is the reported architecture.
    ///
    case unsupportedArchitecture(String)
}
