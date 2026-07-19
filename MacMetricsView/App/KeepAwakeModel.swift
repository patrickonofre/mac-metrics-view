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

    /// Lid-close sub-mode state (feature `lid-close-keep-awake`). Deliberately NOT
    /// persisted: every launch starts `.off` (LIDC-13), unlike the base toggle.
    @Published private(set) var lidClose: LidCloseState = .off

    private let service: SleepAssertionControlling
    private let userDefaults: UserDefaults
    private let lidCloseService: LidCloseSleepControlling
    private let powerSourceMonitor: PowerSourceMonitoring

    /// Tail of the serialized lid-close transition queue. Each request chains behind
    /// the previous one, so helper calls never interleave and the final state matches
    /// the last request (rapid-toggle edge case).
    private var lidCloseTask: Task<Void, Never>?

    /// Most recent power-source reading while the monitor runs; consulted at
    /// activation time to refuse enabling below the battery threshold (LIDC-16).
    private var latestPowerSnapshot: PowerSourceSnapshot?

    /// On init, restores the stored preference and — if it was on — attempts to
    /// re-create the assertion right away (KAWK-06). If the OS refuses it (KAWK-02),
    /// `isActive` reports `false` but the stored preference is left untouched, so the
    /// next launch retries (KAWK-07) instead of silently forgetting the user's intent.
    ///
    /// `lidCloseService`/`powerSourceMonitor` are injectable for tests; `nil` builds
    /// the real implementations here (not as default arguments, which would evaluate
    /// outside the main actor). The lid-close sub-mode is never restored (LIDC-13).
    init(
        userDefaults: UserDefaults,
        service: SleepAssertionControlling = IOPMSleepAssertionService(),
        lidCloseService: LidCloseSleepControlling? = nil,
        powerSourceMonitor: PowerSourceMonitoring? = nil
    ) {
        self.userDefaults = userDefaults
        self.service = service
        self.lidCloseService = lidCloseService ?? HelperLidCloseSleepService()
        self.powerSourceMonitor = powerSourceMonitor ?? IOPSPowerSourceMonitor()
        if KeepAwakeSettings.load(from: userDefaults).isActive {
            isActive = service.activate()
        }
        // Broken-daemon resync: a dropped helper connection means a fresh daemon that
        // no longer tracks the flag — snap the sub-mode off (LIDC-05 direction) rather
        // than keep claiming a flag nobody owns. Goes through the serialized queue so
        // it cannot interleave with a user toggle.
        self.lidCloseService.onConnectionLost = { [weak self] in
            guard let self, self.lidClose == .active else { return }
            self.enqueueLidCloseTransition(false)
        }
    }

    /// Activates or deactivates keep-awake. Idempotent (KAWK-04): a redundant call is a
    /// no-op. If the OS refuses the assertion, `isActive` stays `false` (KAWK-02).
    /// Persists the resulting state (KAWK-05). Turning the base toggle off also
    /// cascades the lid-close sub-mode off (LIDC-04).
    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        if active {
            isActive = service.activate()
        } else {
            service.deactivate()
            isActive = false
            if lidClose != .off {
                enqueueLidCloseTransition(false)
            }
        }
        KeepAwakeSettings(isActive: isActive).save(to: userDefaults)
    }

    func toggle() {
        setActive(!isActive)
    }

    // MARK: - Lid-close sub-mode (feature `lid-close-keep-awake`)

    /// Requests the lid-close sub-mode on or off. Transitions are serialized through
    /// a task chain (rapid toggles: last request wins) and idempotent at execution
    /// time — asking for the state already in force makes no helper call (LIDC-06).
    func setLidCloseActive(_ active: Bool) async {
        await enqueueLidCloseTransition(active).value
    }

    /// Awaits every queued lid-close transition. The quit failsafe (LIDC-11) and
    /// tests use it to observe a settled state after a fire-and-forget cascade.
    func settleLidCloseTransitions() async {
        await lidCloseTask?.value
    }

    @discardableResult
    private func enqueueLidCloseTransition(_ active: Bool) -> Task<Void, Never> {
        let previous = lidCloseTask
        let task = Task { [weak self] in
            await previous?.value
            await self?.performLidCloseTransition(active)
        }
        lidCloseTask = task
        return task
    }

    private func performLidCloseTransition(_ requestedActive: Bool) async {
        if requestedActive {
            // LIDC-06: already active — no helper call. (`.pendingApproval` is NOT
            // active, so a repeat enable retries after the user approves.)
            guard lidClose != .active else { return }
            // LIDC-01: the sub-mode is reachable only while base keep-awake is on.
            guard isActive else { return }

            // The monitor delivers the current reading synchronously on start, so the
            // fail-safe also applies at activation time (LIDC-16 edge case).
            startPowerSourceMonitor()
            if let snapshot = latestPowerSnapshot, LidCloseFailsafePolicy.shouldBlock(snapshot) {
                stopPowerSourceMonitor()
                lidClose = .off
                return
            }

            switch await lidCloseService.activate() {
            case .active:
                lidClose = .active // LIDC-02
            case .pendingApproval:
                stopPowerSourceMonitor()
                lidClose = .pendingApproval // LIDC-08
            case .failed:
                stopPowerSourceMonitor()
                lidClose = .off // LIDC-05: never active without the flag set
            }
        } else {
            guard lidClose != .off else { return } // LIDC-06
            await lidCloseService.deactivate() // LIDC-03/04
            stopPowerSourceMonitor()
            lidClose = .off
        }
    }

    private func startPowerSourceMonitor() {
        powerSourceMonitor.onChange = { [weak self] snapshot in
            guard let self else { return }
            self.latestPowerSnapshot = snapshot
            // LIDC-14: while the sub-mode is active, a reading below the threshold on
            // battery auto-deactivates it through the same serialized queue (redundant
            // readings collapse into the LIDC-06 no-op). The handler only ever turns
            // the sub-mode off — never back on — so reconnecting power cannot re-arm
            // it (LIDC-15), and base keep-awake is not touched here (LIDC-16).
            if self.lidClose == .active, LidCloseFailsafePolicy.shouldBlock(snapshot) {
                self.enqueueLidCloseTransition(false)
            }
        }
        powerSourceMonitor.start()
    }

    private func stopPowerSourceMonitor() {
        powerSourceMonitor.stop()
        powerSourceMonitor.onChange = nil
        latestPowerSnapshot = nil
    }
}
