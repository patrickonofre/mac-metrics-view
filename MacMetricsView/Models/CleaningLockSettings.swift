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
    }

    // MARK: - Properties

    var selectedDuration: TimeInterval

    // MARK: - Init

    init(selectedDuration: TimeInterval = CleaningLockSettings.defaultDuration) {
        self.selectedDuration = selectedDuration
    }

    // MARK: - Persistence

    /// Loads settings from `UserDefaults`, falling back to defaults if the stored
    /// value is missing, non-positive, or not one of the allowed presets.
    static func load(from userDefaults: UserDefaults = .standard) -> CleaningLockSettings {
        let raw = userDefaults.double(forKey: Keys.selectedDuration)
        guard raw > 0, presets.contains(raw) else {
            return CleaningLockSettings()
        }
        return CleaningLockSettings(selectedDuration: raw)
    }

    /// Persists the current settings to `UserDefaults`.
    func save(to userDefaults: UserDefaults = .standard) {
        userDefaults.set(selectedDuration, forKey: Keys.selectedDuration)
    }
}
