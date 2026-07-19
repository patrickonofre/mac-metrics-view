import Foundation
import Combine

/// The Utilities pillar (TD-012): a plain keep-awake toggle. When active, holds a
/// `PreventUserIdleDisplaySleep` power assertion so the display and system do not sleep
/// (Amphetamine/Caffeine-style). Sibling of `CleaningLockModel`.
///
/// Persisted (feature `keep-awake-persistence`, KAWK-05/06/07) via `KeepAwakeSettings`:
/// the last user selection survives app relaunch and Mac restart, and `init` attempts to
/// re-create the real assertion immediately when the stored preference is on. Never
/// bridged upward to `CPUState`'s `objectWillChange` (same contract as `lock`/`ambient`/
/// `token`) — `ActionsTab` observes this model directly at the point of use.
@MainActor
final class KeepAwakeModel: ObservableObject {
    /// Whether a sleep assertion is currently held. Read-only to the UI; mutated only
    /// through `setActive`/`toggle` so it always tracks the real assertion state.
    @Published private(set) var isActive: Bool = false

    private let service: SleepAssertionControlling
    private let userDefaults: UserDefaults

    /// On init, restores the stored preference and — if it was on — attempts to
    /// re-create the assertion right away (KAWK-06). If the OS refuses it (KAWK-02),
    /// `isActive` reports `false` but the stored preference is left untouched, so the
    /// next launch retries (KAWK-07) instead of silently forgetting the user's intent.
    init(userDefaults: UserDefaults, service: SleepAssertionControlling = IOPMSleepAssertionService()) {
        self.userDefaults = userDefaults
        self.service = service
        if KeepAwakeSettings.load(from: userDefaults).isActive {
            isActive = service.activate()
        }
    }

    /// Activates or deactivates keep-awake. Idempotent (KAWK-04): a redundant call is a
    /// no-op. If the OS refuses the assertion, `isActive` stays `false` (KAWK-02).
    /// Persists the resulting state (KAWK-05).
    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        if active {
            isActive = service.activate()
        } else {
            service.deactivate()
            isActive = false
        }
        KeepAwakeSettings(isActive: isActive).save(to: userDefaults)
    }

    func toggle() {
        setActive(!isActive)
    }
}
