// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

///
/// What a command run inside a container produced.
///
/// This is returned by ``NextcloudContainerManager/runOCC(_:environment:timeout:inContainer:)`` and ``NextcloudContainerManager/runExec(_:user:workingDirectory:environment:waitsForExit:timeout:inContainer:)``, and it is also carried by ``NextcloudContainerManagerError/commandFailed(command:result:)`` so that a command which fails explains itself in the words of the program that ran, rather than only through a number.
///
public struct CommandResult: Sendable {
    ///
    /// The status the command exited with.
    ///
    /// A result handed back from a successful call always holds zero, because a non-zero status is thrown as ``NextcloudContainerManagerError/commandFailed(command:result:)`` instead of returned. The value therefore only carries information on the result attached to that error. A command that is not waited for yields no result at all rather than one with an invented status.
    ///
    public let exitCode: Int

    ///
    /// Everything the command wrote to its standard output, decoded as UTF-8.
    ///
    /// This is where `occ` puts what it was asked for, so it is the half to read after a query such as `user:list` or `config:app:get`. Bytes that are not valid UTF-8 are replaced rather than rejected, because a command's output is diagnostic material and is more useful slightly damaged than absent.
    ///
    public let standardOutput: String

    ///
    /// Everything the command wrote to its standard error, decoded as UTF-8.
    ///
    /// This is where `occ` explains a refusal, so it is the half to read on a failure. Decoding follows the same rule as ``standardOutput``.
    ///
    public let standardError: String

    ///
    /// Create a result.
    ///
    /// - Parameters:
    ///     - exitCode: The status the command exited with.
    ///     - standardOutput: What the command wrote to its standard output.
    ///     - standardError: What the command wrote to its standard error.
    ///
    init(exitCode: Int, standardOutput: String, standardError: String) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}
