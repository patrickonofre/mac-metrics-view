import Foundation

/// Persisted preferences for the cleaning-lock feature.
///
/// Follows the same `load(from:)` / `save(to:)` pattern as `MetricDisplaySettings`.
struct CleaningLockSettings: Equatable {

    // MARK: - Presets

    /// Available lock durations in seconds.
    static let presets: [TimeInterval] = [15, 30, 60, 120, 300]

    /// Default lock duration used when no valid preference has been stored.
    static let defaultDuration: TimeInterval = 30

    // MARK: - UserDefaults keys

    private enum Keys {
        static let selectedDuration = "CleaningLockSettings.selectedDuration"
        static let isEnabled = "CleaningLockSettings.isEnabled"
    }

    // MARK: - Properties

    var selectedDuration: TimeInterval

    /// Feature-level opt-in (`keep-awake`-style gate, feature `cleaning-lock-opt-in`,
    /// CLNGT-01). While `false`, nothing in the cleaning-lock chain touches
    /// Accessibility: no `AXIsProcessTrusted()` check, no grant-tracker writes, no
    /// launch-time auto-popover nudge, no warning banner.
    var isEnabled: Bool

    // MARK: - Init

    init(selectedDuration: TimeInterval = CleaningLockSettings.defaultDuration, isEnabled: Bool = false) {
        self.selectedDuration = selectedDuration
        self.isEnabled = isEnabled
    }

    // MARK: - Persistence

    /// Loads settings from `UserDefaults`, falling back to defaults if the stored
    /// duration is missing, non-positive, or not one of the allowed presets. `isEnabled`
    /// defaults to `false` when absent (`bool(forKey:)` returns `false` for a missing
    /// key) — use `resolved(from:isCurrentlyTrusted:)` at launch instead of this method
    /// directly when the one-time migration bootstrap should apply.
    static func load(from userDefaults: UserDefaults = .standard) -> CleaningLockSettings {
        let raw = userDefaults.double(forKey: Keys.selectedDuration)
        let duration = (raw > 0 && presets.contains(raw)) ? raw : defaultDuration
        return CleaningLockSettings(
            selectedDuration: duration,
            isEnabled: userDefaults.bool(forKey: Keys.isEnabled)
        )
    }

    /// Resolves settings to use at launch, applying the one-time `isEnabled` migration
    /// bootstrap (CLNGT-06/CLNGT-07): if no `isEnabled` preference has ever been stored
    /// (`object(forKey:) == nil`, distinct from an explicitly-stored `false`), seeds it
    /// from `isCurrentlyTrusted` and persists immediately so the bootstrap runs exactly
    /// once. This preserves users who already had Accessibility granted (and were
    /// therefore already active users of the feature) without silently opting them out.
    /// Mirrors `MetricDisplaySettings.resolved(from:)`'s flag-guarded migration pattern.
    static func resolved(from userDefaults: UserDefaults = .standard, isCurrentlyTrusted: Bool) -> CleaningLockSettings {
        guard userDefaults.object(forKey: Keys.isEnabled) == nil else {
            return load(from: userDefaults)
        }
        var settings = load(from: userDefaults)
        settings.isEnabled = isCurrentlyTrusted
        settings.save(to: userDefaults)
        return settings
    }

    /// Persists the current settings to `UserDefaults`.
    func save(to userDefaults: UserDefaults = .standard) {
        userDefaults.set(selectedDuration, forKey: Keys.selectedDuration)
        userDefaults.set(isEnabled, forKey: Keys.isEnabled)
    }
}
