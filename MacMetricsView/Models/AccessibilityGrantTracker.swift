import Foundation

/// Tracks the app version at which Accessibility (AX) permission was last seen
/// granted, so the UI can tell a *first-time* grant apart from a grant that an
/// app update silently reset.
///
/// macOS keys the AX grant to the build's cdhash for ad-hoc–signed apps (this
/// app's posture, see `docs/TECH_DECISIONS.md` TD-010). Each new version has a
/// different cdhash, so after an update `AXIsProcessTrusted()` returns `false`
/// even though System Settings still lists the stale entry as ON. Toggling that
/// stale entry does not re-grant the new build — it must be removed and re-added.
///
/// Follows the same `load(from:)` / `save(to:)` pattern as the other settings
/// models. Persisted as a single optional string; absent means "never granted".
struct AccessibilityGrantTracker: Equatable {

    private enum Keys {
        static let lastGrantedVersion = "AccessibilityGrantTracker.lastGrantedVersion"
    }

    /// The app version string at which AX was last observed as granted, if any.
    let lastGrantedVersion: String?

    init(lastGrantedVersion: String? = nil) {
        self.lastGrantedVersion = lastGrantedVersion
    }

    /// True when the current build is not trusted but a *different, earlier*
    /// version was — i.e. an update reset the grant. A revoke on the same
    /// version (`lastGrantedVersion == currentVersion`) is not a reset, and a
    /// never-granted state (`lastGrantedVersion == nil`) is a normal first grant.
    func wasResetByUpdate(isTrusted: Bool, currentVersion: String) -> Bool {
        guard !isTrusted, let last = lastGrantedVersion else { return false }
        return last != currentVersion
    }

    /// Returns a copy recording `version` as the latest version seen granted.
    func recordingGrant(version: String) -> AccessibilityGrantTracker {
        AccessibilityGrantTracker(lastGrantedVersion: version)
    }

    // MARK: - Persistence

    static func load(from userDefaults: UserDefaults = .standard) -> AccessibilityGrantTracker {
        AccessibilityGrantTracker(lastGrantedVersion: userDefaults.string(forKey: Keys.lastGrantedVersion))
    }

    func save(to userDefaults: UserDefaults = .standard) {
        if let lastGrantedVersion {
            userDefaults.set(lastGrantedVersion, forKey: Keys.lastGrantedVersion)
        } else {
            userDefaults.removeObject(forKey: Keys.lastGrantedVersion)
        }
    }
}
