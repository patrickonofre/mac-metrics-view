import Foundation

/// Remembers the app version for which the proactive "open the recovery card"
/// nudge has already fired, so an update-reset surfaces the popover exactly once
/// per reset event instead of on every launch.
///
/// The nudge is keyed per version (not a plain `Bool`) so a *future* update that
/// resets the grant again gets its own one-time nudge — see ADR-003. Follows the
/// same `load(from:)` / `save(to:)` pattern as `AccessibilityGrantTracker`; the
/// single field is optional, where absent means "never nudged".
struct AccessibilityNudgeTracker: Equatable {

    private enum Keys {
        static let lastNudgedVersion = "AccessibilityNudgeTracker.lastNudgedVersion"
    }

    /// The app version for which the auto-open nudge last fired, if any.
    let lastNudgedVersion: String?

    init(lastNudgedVersion: String? = nil) {
        self.lastNudgedVersion = lastNudgedVersion
    }

    /// Whether the nudge should fire for `version` — true only when no nudge has
    /// been recorded for that exact version (including the fresh, never-nudged
    /// state, where the stored value is `nil`).
    func shouldNudge(forVersion version: String) -> Bool {
        lastNudgedVersion != version
    }

    /// Returns a copy recording that the nudge fired for `version`.
    func recordingNudge(version: String) -> AccessibilityNudgeTracker {
        AccessibilityNudgeTracker(lastNudgedVersion: version)
    }

    // MARK: - Persistence

    static func load(from userDefaults: UserDefaults = .standard) -> AccessibilityNudgeTracker {
        AccessibilityNudgeTracker(
            lastNudgedVersion: userDefaults.string(forKey: Keys.lastNudgedVersion)
        )
    }

    func save(to userDefaults: UserDefaults = .standard) {
        if let lastNudgedVersion {
            userDefaults.set(lastNudgedVersion, forKey: Keys.lastNudgedVersion)
        } else {
            userDefaults.removeObject(forKey: Keys.lastNudgedVersion)
        }
    }
}
