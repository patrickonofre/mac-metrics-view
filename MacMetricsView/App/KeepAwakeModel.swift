import Foundation
import Combine

/// The Utilities pillar (TD-012): a plain keep-awake toggle. When active, holds a
/// `PreventUserIdleDisplaySleep` power assertion so the display and system do not sleep
/// (Amphetamine/Caffeine-style). Sibling of `CleaningLockModel`.
///
/// Deliberately **not** persisted and never bridged upward to `CPUState`'s
/// `objectWillChange` (same contract as `lock`/`ambient`/`token`): the app always
/// launches with keep-awake off (KAWK-03) so a forgotten assertion can't drain a battery
/// across sessions, and `ActionsTab` observes this model directly at the point of use.
@MainActor
final class KeepAwakeModel: ObservableObject {
    /// Whether a sleep assertion is currently held. Read-only to the UI; mutated only
    /// through `setActive`/`toggle` so it always tracks the real assertion state.
    @Published private(set) var isActive: Bool = false

    private let service: SleepAssertionControlling

    init(service: SleepAssertionControlling = IOPMSleepAssertionService()) {
        self.service = service
    }

    /// Activates or deactivates keep-awake. Idempotent (KAWK-04): a redundant call is a
    /// no-op. If the OS refuses the assertion, `isActive` stays `false` (KAWK-02).
    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        if active {
            isActive = service.activate()
        } else {
            service.deactivate()
            isActive = false
        }
    }

    func toggle() {
        setActive(!isActive)
    }
}
