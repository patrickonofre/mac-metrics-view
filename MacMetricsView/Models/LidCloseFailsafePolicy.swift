import Foundation

/// Battery fail-safe rule for the lid-close keep-awake sub-mode (feature
/// `lid-close-keep-awake`). Pure — Foundation only — so every branch is unit-testable.
///
/// Applied in two places: on each power-source change while the sub-mode is active
/// (LIDC-14) and at activation time, refusing enable when already below threshold on
/// battery (LIDC-16 edge case). AC power never blocks, regardless of level.
struct LidCloseFailsafePolicy {
    /// Fixed threshold (spec decision: matches Amphetamine default; not configurable).
    /// Blocking triggers strictly below this level, so exactly 10% still allows.
    static let batteryThresholdPercent = 10

    /// `true` when the sub-mode must be (or stay) off: below 10% while on battery.
    static func shouldBlock(levelPercent: Int, isOnBattery: Bool) -> Bool {
        isOnBattery && levelPercent < batteryThresholdPercent
    }

    /// Convenience overload for the monitor's snapshot type.
    static func shouldBlock(_ snapshot: PowerSourceSnapshot) -> Bool {
        shouldBlock(levelPercent: snapshot.levelPercent, isOnBattery: snapshot.isOnBattery)
    }
}
