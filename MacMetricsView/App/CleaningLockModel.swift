import Foundation
import Combine

/// The Utilities pillar (TD-012): the cleaning-mode input lock (duration, phase,
/// countdown) composing the `AccessibilityRecoveryModel` that gates it — the lock
/// requires the Accessibility grant to suppress input via `CGEventTap` (ADR-002).
/// Extracted from `CPUState` (spec `spec-cpustate-pillar-decouple`, task-004).
///
/// `recovery` is nested inside this model; SwiftUI's nested-`ObservableObject` does not
/// propagate `objectWillChange` through containment, so this model bridges `recovery`'s
/// changes into its own (intra-pillar only — `CPUState` does not bridge `lock` upward in
/// turn; UI observes `lock` directly at the point of use, e.g. `ActionsTab`,
/// `LockOverlayView`, and `PopoverView`'s recovery banner).
@MainActor
final class CleaningLockModel: ObservableObject {
    /// Updated by `AppDelegate` via `updateState(phase:remaining:)` as the lock service
    /// ticks (1Hz while locked).
    @Published private(set) var phase: LockPhase = .idle
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var settings: CleaningLockSettings

    let recovery: AccessibilityRecoveryModel

    /// Called by the UI when the user taps Iniciar; `AppDelegate` wires the actual lock
    /// start.
    var onStartLock: ((TimeInterval) -> Void)?

    private let userDefaults: UserDefaults
    private var recoveryObservation: AnyCancellable?

    init(
        userDefaults: UserDefaults,
        accessibilityAuthorization: AccessibilityAuthorizationProtocol,
        accessibilityProbe: AccessibilityProbing,
        currentAppVersion: String
    ) {
        self.userDefaults = userDefaults
        settings = CleaningLockSettings.load(from: userDefaults)
        recovery = AccessibilityRecoveryModel(
            userDefaults: userDefaults,
            authorization: accessibilityAuthorization,
            probe: accessibilityProbe,
            currentAppVersion: currentAppVersion
        )
        recoveryObservation = recovery.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
    }

    /// Persists the selected duration and updates the in-memory setting.
    func selectDuration(_ duration: TimeInterval) {
        guard CleaningLockSettings.presets.contains(duration) else { return }
        settings.selectedDuration = duration
        settings.save(to: userDefaults)
    }

    /// Fires `onStartLock` with the currently selected duration. `AppDelegate` owns the
    /// lock service and responds to this callback.
    func start() {
        onStartLock?(settings.selectedDuration)
    }

    /// Called by `AppDelegate` each tick and on session end to keep the UI in sync.
    func updateState(phase: LockPhase, remaining: TimeInterval) {
        self.phase = phase
        self.remaining = remaining
    }
}
