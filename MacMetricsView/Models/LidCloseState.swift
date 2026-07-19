import Foundation

/// UI-facing state of the lid-close keep-awake sub-mode (feature
/// `lid-close-keep-awake`). Deliberately NOT persisted: the sub-mode always starts
/// `.off` on launch (LIDC-13) so a relaunch can never silently re-disable sleep.
enum LidCloseState: Equatable {
    /// Sub-mode inactive; system sleep behaves normally.
    case off
    /// Helper daemon registered but waiting for user approval in
    /// System Settings → Login Items (LIDC-08). Sub-mode is NOT active.
    case pendingApproval
    /// Helper confirmed the sleep-disabled flag is set (LIDC-02).
    case active
}

/// Result of asking the helper service to activate the sub-mode. Mirrors the three
/// reachable `LidCloseState` outcomes so `KeepAwakeModel` maps 1:1.
enum LidCloseActivationOutcome: Equatable {
    /// Flag set; sub-mode is live.
    case active
    /// Daemon registration requires user approval; retry after approval (LIDC-08).
    case pendingApproval
    /// Registration or the XPC call failed/was refused — sub-mode must show
    /// inactive (LIDC-05, LIDC-09).
    case failed
}

/// One power-source reading for the battery fail-safe (LIDC-14). Pure value type so
/// the fail-safe policy and model wiring are unit-testable without IOKit.
struct PowerSourceSnapshot: Equatable {
    /// Battery charge 0–100.
    let levelPercent: Int
    /// `true` when running on battery power (not AC).
    let isOnBattery: Bool
}
