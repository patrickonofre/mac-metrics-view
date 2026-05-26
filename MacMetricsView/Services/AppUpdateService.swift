import Foundation

/// Contract the app uses to check for and configure updates, with no dependency
/// on Sparkle. The concrete Sparkle-backed implementation lives in
/// `SparkleUpdateService` (compiled only when the framework is present); the SPM
/// build resolves to `NoOpUpdateService` so `swift test`/`swift run` stay
/// Sparkle-free.
@MainActor
protocol AppUpdateService: AnyObject {
    /// Whether a check can be started right now (false when no updater is linked).
    var canCheckForUpdates: Bool { get }

    /// Triggers a user-initiated update check.
    func checkForUpdates()

    /// Enables or disables Sparkle's background automatic checks.
    func setAutomaticChecks(_ enabled: Bool)
}

/// Inert implementation used wherever Sparkle is not linked (the SPM executable).
/// Every method is a no-op and no check is ever possible.
@MainActor
final class NoOpUpdateService: AppUpdateService {
    var canCheckForUpdates: Bool { false }

    func checkForUpdates() {}

    func setAutomaticChecks(_ enabled: Bool) {}
}

/// Single decision point for which implementation the app uses. Resolves to the
/// real Sparkle wrapper when the framework is embedded (Xcode `.app`), and to the
/// no-op otherwise (SPM `swift run`/`swift test`).
@MainActor
func makeAppUpdateService() -> AppUpdateService {
    #if canImport(Sparkle)
    return SparkleUpdateService()
    #else
    return NoOpUpdateService()
    #endif
}
