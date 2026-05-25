import Foundation

/// Reason why a cleaning-lock session ended.
enum LockEndReason {
    /// The timer reached zero naturally.
    case expired
    /// The user triggered the emergency abort (hold Esc for 3 s).
    case aborted
    /// The app was terminated while the lock was active.
    case terminated
}
