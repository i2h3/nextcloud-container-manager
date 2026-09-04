// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Lets a cancelled task interrupt a request that is blocked on a socket.
///
/// A request runs on a dispatch queue and blocks in `recv` until the Docker Engine answers, which is invisible to Swift concurrency: the continuation it suspends is resumed by the socket and by nothing else, so cancelling the surrounding task otherwise has no effect until the daemon happens to reply. This hands the file descriptor to the cancellation handler so it can be shut down instead, which makes the blocked call return and lets the request end as a `CancellationError`.
///
/// The descriptor is only ever touched while the lock is held, and it is given up here before it is closed, so a cancellation arriving late cannot shut down a descriptor number the kernel has already handed to somebody else.
///
final class CancellableSocket: @unchecked Sendable {
    ///
    /// Guards both stored properties, and the shutdown that reads one of them.
    ///
    private let lock = NSLock()

    ///
    /// The socket to interrupt, while a request owns one.
    ///
    private var fileDescriptor: Int32?

    ///
    /// Whether the surrounding task has been cancelled.
    ///
    private var cancelled = false

    ///
    /// Whether the surrounding task has been cancelled.
    ///
    var isCancelled: Bool {
        lock.lock()

        defer { lock.unlock() }

        return cancelled
    }

    ///
    /// Takes ownership of a socket so that cancelling the task can interrupt it.
    ///
    /// - Parameters:
    ///     - fileDescriptor: The socket to interrupt.
    ///
    /// - Returns: Whether the socket was adopted, which is `false` when the task was already cancelled and the request should not begin at all.
    ///
    func adopt(_ fileDescriptor: Int32) -> Bool {
        lock.lock()

        defer { lock.unlock() }

        guard !cancelled else {
            return false
        }

        self.fileDescriptor = fileDescriptor

        return true
    }

    ///
    /// Gives up ownership of the socket, after which it is safe for the caller to close it.
    ///
    func release() {
        lock.lock()

        defer { lock.unlock() }

        fileDescriptor = nil
    }

    ///
    /// Records the cancellation and interrupts the socket a request is blocked on, if there is one.
    ///
    /// Shutting the socket down rather than closing it wakes the blocked call without retiring the descriptor, so the request itself remains the only thing that closes it.
    ///
    func cancel() {
        lock.lock()

        defer { lock.unlock() }

        cancelled = true

        if let fileDescriptor {
            shutdown(fileDescriptor, SHUT_RDWR)
        }
    }
}
