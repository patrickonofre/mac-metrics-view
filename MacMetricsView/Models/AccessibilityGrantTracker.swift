import Foundation

/// Tracks the app versions seen on this machine so the UI can tell a
/// *first-time* Accessibility (AX) grant apart from a grant that an app update
/// silently reset.
///
/// macOS keys the AX grant to the build's cdhash for ad-hoc–signed apps (this
/// app's historical posture, see `docs/TECH_DECISIONS.md` TD-010). Each new
/// version had a different cdhash, so after an update `AXIsProcessTrusted()`
/// returns `false` even though System Settings still lists the stale entry as
/// ON. Releases are now signed with a stable self-signed certificate so the
/// designated requirement (and thus the grant) survives future updates, but the
/// one-time transition from the last ad-hoc build still drops the grant — and
/// this tracker is what surfaces the recovery guidance for it.
///
/// Two versions are remembered:
/// - `lastGrantedVersion`: the version last *observed as granted*. Strong
///   evidence the grant existed.
/// - `lastSeenVersion`: the version last *run at all*, granted or not. This lets
///   us detect an update reset even for users who never had the grant recorded
///   (e.g. updating from a build that predated this tracker).
///
/// Follows the same `load(from:)` / `save(to:)` pattern as the other settings
/// models. Both fields are optional; absent means "never seen / never granted".
struct AccessibilityGrantTracker: Equatable {

    private enum Keys {
        static let lastGrantedVersion = "AccessibilityGrantTracker.lastGrantedVersion"
        static let lastSeenVersion = "AccessibilityGrantTracker.lastSeenVersion"
    }

    /// The app version string at which AX was last observed as granted, if any.
    let lastGrantedVersion: String?

    /// The app version string last run on this machine, granted or not, if any.
    let lastSeenVersion: String?

    init(lastGrantedVersion: String? = nil, lastSeenVersion: String? = nil) {
        self.lastGrantedVersion = lastGrantedVersion
        self.lastSeenVersion = lastSeenVersion
    }

    /// True when the current build is not trusted but a *different, earlier*
    /// version of the app ran here before — i.e. an update reset the grant. The
    /// prior version is the granted one when known, otherwise the merely-seen
    /// one. A revoke on the same version is not a reset, and a never-seen state
    /// is a normal first grant.
    func wasResetByUpdate(isTrusted: Bool, currentVersion: String) -> Bool {
        guard !isTrusted else { return false }
        guard let priorVersion = lastGrantedVersion ?? lastSeenVersion else { return false }
        return priorVersion != currentVersion
    }

    /// Returns a copy recording `version` as the latest version seen granted
    /// (also counts as seen).
    func recordingGrant(version: String) -> AccessibilityGrantTracker {
        AccessibilityGrantTracker(lastGrantedVersion: version, lastSeenVersion: version)
    }

    /// Returns a copy recording `version` as the latest version run, preserving
    /// any previously recorded granted version.
    func recordingSeen(version: String) -> AccessibilityGrantTracker {
        AccessibilityGrantTracker(lastGrantedVersion: lastGrantedVersion, lastSeenVersion: version)
    }

    // MARK: - Persistence

    static func load(from userDefaults: UserDefaults = .standard) -> AccessibilityGrantTracker {
        AccessibilityGrantTracker(
            lastGrantedVersion: userDefaults.string(forKey: Keys.lastGrantedVersion),
            lastSeenVersion: userDefaults.string(forKey: Keys.lastSeenVersion)
        )
    }

    func save(to userDefaults: UserDefaults = .standard) {
        if let lastGrantedVersion {
            userDefaults.set(lastGrantedVersion, forKey: Keys.lastGrantedVersion)
        } else {
            userDefaults.removeObject(forKey: Keys.lastGrantedVersion)
        }
        if let lastSeenVersion {
            userDefaults.set(lastSeenVersion, forKey: Keys.lastSeenVersion)
        } else {
            userDefaults.removeObject(forKey: Keys.lastSeenVersion)
        }
    }
}
