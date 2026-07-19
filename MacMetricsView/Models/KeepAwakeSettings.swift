import Foundation

/// Persisted preference for the keep-awake toggle (feature `keep-awake-persistence`,
/// KAWK-05/KAWK-06).
///
/// Follows the same `load(from:)` / `save(to:)` pattern as `CleaningLockSettings`.
struct KeepAwakeSettings: Equatable {

    // MARK: - UserDefaults keys

    private enum Keys {
        static let isActive = "KeepAwakeSettings.isActive"
    }

    // MARK: - Properties

    var isActive: Bool

    // MARK: - Init

    init(isActive: Bool = false) {
        self.isActive = isActive
    }

    // MARK: - Persistence

    /// Loads settings from `UserDefaults`, defaulting to `false` when no value has been
    /// stored yet (`bool(forKey:)` returns `false` for a missing key).
    static func load(from userDefaults: UserDefaults = .standard) -> KeepAwakeSettings {
        KeepAwakeSettings(isActive: userDefaults.bool(forKey: Keys.isActive))
    }

    /// Persists the current settings to `UserDefaults`.
    func save(to userDefaults: UserDefaults = .standard) {
        userDefaults.set(isActive, forKey: Keys.isActive)
    }
}
