import Foundation

/// Contract the app uses to check for updates and learn about a newer available
/// version, with no dependency on Sparkle. The concrete Sparkle-backed
/// implementation lives in `SparkleUpdateService` (compiled only when the
/// framework is present); the SPM build resolves to `NoOpUpdateService` so
/// `swift test`/`swift run` stay Sparkle-free.
///
/// Background automatic checks are governed solely by `Info.plist`
/// (`SUEnableAutomaticChecks=YES`); there is no user-facing toggle.
@MainActor
protocol AppUpdateService: AnyObject {
    /// Whether a check can be started right now (false when no updater is linked).
    var canCheckForUpdates: Bool { get }

    /// Notifies with the newest available version string, or `nil` when none is
    /// available. Invoked on the main actor by a passive probe.
    var onAvailableVersionChange: ((String?) -> Void)? { get set }

    /// Triggers a user-initiated, interactive update check (shows Sparkle UI).
    func checkForUpdates()

    /// Passive check that consults the appcast without showing any UI and reports
    /// the result through `onAvailableVersionChange`.
    func probeForUpdateInformation()
}

/// Inert implementation used wherever Sparkle is not linked (the SPM executable).
/// Every method is a no-op and no check is ever possible.
@MainActor
final class NoOpUpdateService: AppUpdateService {
    var canCheckForUpdates: Bool { false }

    var onAvailableVersionChange: ((String?) -> Void)?

    func checkForUpdates() {}

    func probeForUpdateInformation() {}
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
