import Foundation

/// Persisted preferences for in-app auto-update (Sparkle).
///
/// Follows the same `load(from:)` / `save(to:)` pattern as
/// `MetricVisibilitySettings`. Pure value type, free of UI and Sparkle, so it
/// is unit-testable under the SPM `swift test` build.
struct UpdateSettings: Equatable {

    // MARK: - UserDefaults keys

    private enum Keys {
        static let automaticChecks = "UpdateSettings.automaticallyChecksForUpdates"
    }

    // MARK: - Properties

    /// Whether the app checks for updates automatically in the background.
    var automaticallyChecksForUpdates: Bool

    // MARK: - Init

    init(automaticallyChecksForUpdates: Bool = true) {
        self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
    }

    // MARK: - Persistence

    /// Loads settings from `UserDefaults`. A missing or invalid value reads as the
    /// default (`true`), so first launch and corrupted state both opt in.
    static func load(from userDefaults: UserDefaults = .standard) -> UpdateSettings {
        guard userDefaults.object(forKey: Keys.automaticChecks) != nil else {
            return UpdateSettings()
        }
        return UpdateSettings(
            automaticallyChecksForUpdates: userDefaults.bool(forKey: Keys.automaticChecks)
        )
    }

    /// Persists the current settings to `UserDefaults`.
    func save(to userDefaults: UserDefaults = .standard) {
        userDefaults.set(automaticallyChecksForUpdates, forKey: Keys.automaticChecks)
    }
}
