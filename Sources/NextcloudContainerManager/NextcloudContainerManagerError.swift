// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

///
/// Errors that can be thrown by `NextcloudContainerManager`.
///
public enum NextcloudContainerManagerError: Error {
    /// Docker Desktop was not found at its expected path (`/Applications/Docker.app`).
    case dockerDesktopNotFound
    /// Docker Desktop was found but could not be launched.
    case dockerDesktopLaunchFailed
}
