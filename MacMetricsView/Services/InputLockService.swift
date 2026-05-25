import Foundation

// MARK: - Phase

/// Observable phase of a cleaning-lock session.
enum LockPhase: Equatable {
    case idle
    case locked
}

// MARK: - Protocol

/// Manages a time-bounded input-suppression session.
///
/// Implementations must guarantee that input is always released when the
/// timer expires, the user aborts, or the app terminates.
///
/// Adopt `@MainActor` in the concrete type so `phase` and `remaining` are
/// safe to read from SwiftUI without explicit dispatching.
@MainActor
protocol InputLockServiceProtocol: AnyObject {
    /// Current phase of the lock session.
    var phase: LockPhase { get }

    /// Seconds remaining in the current session; 0 when idle.
    var remaining: TimeInterval { get }

    /// Called once per second with the updated `remaining` value (including 0 at expiry).
    var onTick: ((TimeInterval) -> Void)? { get set }

    /// Called when a session ends, with the reason.
    var onEnd: ((LockEndReason) -> Void)? { get set }

    /// Starts a new session of `duration` seconds.
    /// No-op if already `.locked`.
    func start(duration: TimeInterval)

    /// Stops the current session for the given reason.
    /// No-op if already `.idle`.
    func stop(reason: LockEndReason)
}
