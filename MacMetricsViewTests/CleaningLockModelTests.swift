import XCTest
import Combine
@testable import MacMetricsView

/// Direct tests for `CleaningLockModel` extracted from `CPUState` (task-004). Exercises
/// the model standalone (no `CPUState`) and proves the intra-pillar bridge: mutating the
/// nested `AccessibilityRecoveryModel` must still publish through `CleaningLockModel`'s
/// own `objectWillChange` (nested `ObservableObject`s do not propagate on their own).
@MainActor
final class CleaningLockModelTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "CleaningLockModelTests.\(UUID().uuidString)")!
    }

    private func makeModel(userDefaults: UserDefaults? = nil) -> CleaningLockModel {
        CleaningLockModel(
            userDefaults: userDefaults ?? makeDefaults(),
            accessibilityAuthorization: FakeAccessibilityAuthorization(isTrusted: false),
            accessibilityProbe: FakeAccessibilityProbe(),
            currentAppVersion: "2.0.0"
        )
    }

    func testInitialStateIsIdleWithDefaultSettings() {
        let model = makeModel()
        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(model.remaining, 0)
        XCTAssertEqual(model.settings.selectedDuration, CleaningLockSettings.defaultDuration)
    }

    func testSelectDurationPersistsAValidPreset() {
        let defaults = makeDefaults()
        let model = makeModel(userDefaults: defaults)

        model.selectDuration(120)

        XCTAssertEqual(model.settings.selectedDuration, 120)
        XCTAssertEqual(CleaningLockSettings.load(from: defaults).selectedDuration, 120)
    }

    func testSelectDurationIgnoresNonPresetValue() {
        let model = makeModel()
        let before = model.settings.selectedDuration

        model.selectDuration(999)

        XCTAssertEqual(model.settings.selectedDuration, before)
    }

    func testStartFiresOnStartLockWithSelectedDuration() {
        let model = makeModel()
        model.selectDuration(60)
        var started: TimeInterval?
        model.onStartLock = { started = $0 }

        model.start()

        XCTAssertEqual(started, 60)
    }

    func testUpdateStatePublishesPhaseAndRemaining() {
        let model = makeModel()
        model.updateState(phase: .locked, remaining: 12)
        XCTAssertEqual(model.phase, .locked)
        XCTAssertEqual(model.remaining, 12)
    }

    func testRecoveryMutationBridgesThroughLockObjectWillChange() {
        let model = makeModel()
        var fired = false
        let cancellable = model.objectWillChange.sink { fired = true }

        model.recovery.beginRecovery()

        XCTAssertTrue(
            fired,
            "CleaningLockModel must bridge its nested AccessibilityRecoveryModel — SwiftUI views observing `lock` need recovery changes to invalidate it too"
        )
        cancellable.cancel()
    }

    // MARK: - Enable/disable policy (feature cleaning-lock-opt-in)

    // CLNGT-06: no stored preference + already trusted → resolves enabled, and init
    // immediately re-evaluates so `recovery.isGranted` reflects reality with no user
    // action (CLNGT-01).
    func testInitWithTrustedAuthorizationAndNoStoredPreferenceEnablesAndEvaluates() {
        let model = CleaningLockModel(
            userDefaults: makeDefaults(),
            accessibilityAuthorization: FakeAccessibilityAuthorization(isTrusted: true),
            accessibilityProbe: FakeAccessibilityProbe(),
            currentAppVersion: "2.0.0"
        )

        XCTAssertTrue(model.settings.isEnabled)
        XCTAssertTrue(model.recovery.isGranted)
    }

    // CLNGT-07/CLNGT-01: no stored preference + untrusted → resolves disabled, and init
    // never touches the recovery model (no AXIsProcessTrusted() call, no tracker write).
    func testInitWithUntrustedAuthorizationAndNoStoredPreferenceStaysDisabledAndNeverEvaluates() {
        let defaults = makeDefaults()

        let model = CleaningLockModel(
            userDefaults: defaults,
            accessibilityAuthorization: FakeAccessibilityAuthorization(isTrusted: false),
            accessibilityProbe: FakeAccessibilityProbe(),
            currentAppVersion: "2.0.0"
        )

        XCTAssertFalse(model.settings.isEnabled)
        XCTAssertFalse(model.recovery.isGranted)
        let tracker = AccessibilityGrantTracker.load(from: defaults)
        XCTAssertNil(tracker.lastGrantedVersion)
        XCTAssertNil(tracker.lastSeenVersion, "a disabled feature must never write the grant tracker, even at launch")
    }

    // CLNGT-04: turning on immediately re-evaluates (no native prompt) and persists.
    func testSetEnabledTrueRefreshesAuthorizationAndPersists() {
        let defaults = makeDefaults()
        let auth = FakeAccessibilityAuthorization(isTrusted: true)
        let model = CleaningLockModel(
            userDefaults: defaults,
            accessibilityAuthorization: auth,
            accessibilityProbe: FakeAccessibilityProbe(),
            currentAppVersion: "2.0.0"
        )
        // Starts disabled: force it off first (isTrusted:true would auto-enable via
        // migration) so this test exercises the explicit turn-on path in isolation.
        model.setEnabled(false)

        model.setEnabled(true)

        XCTAssertTrue(model.settings.isEnabled)
        XCTAssertTrue(CleaningLockSettings.load(from: defaults).isEnabled)
        XCTAssertTrue(model.recovery.isGranted)
        XCTAssertEqual(auth.promptCallCount, 0, "turning the toggle on must never fire the native permission prompt")
    }

    // CLNGT-05: turning off persists immediately.
    func testSetEnabledFalsePersists() {
        let defaults = makeDefaults()
        let model = CleaningLockModel(
            userDefaults: defaults,
            accessibilityAuthorization: FakeAccessibilityAuthorization(isTrusted: true),
            accessibilityProbe: FakeAccessibilityProbe(),
            currentAppVersion: "2.0.0"
        )

        model.setEnabled(false)

        XCTAssertFalse(model.settings.isEnabled)
        XCTAssertFalse(CleaningLockSettings.load(from: defaults).isEnabled)
    }

    // CLNGT-08: the toggle is a no-op while a session is active or applying.
    func testSetEnabledIsNoOpWhileLocked() {
        let model = makeModel()
        model.updateState(phase: .locked, remaining: 10)

        model.setEnabled(true)

        XCTAssertFalse(model.settings.isEnabled, "toggling must be blocked while a lock session is active")
    }

    // CLNGT-01: evaluateLaunchNudgeIfEnabled only forwards when the feature is enabled.
    func testEvaluateLaunchNudgeIfEnabledForwardsOnlyWhenEnabled() {
        let defaults = makeDefaults()
        let model = CleaningLockModel(
            userDefaults: defaults,
            accessibilityAuthorization: FakeAccessibilityAuthorization(isTrusted: true),
            accessibilityProbe: FakeAccessibilityProbe(),
            currentAppVersion: "2.0.0"
        )
        var openCount = 0
        model.recovery.onRequestOpenPopover = { openCount += 1 }

        model.setEnabled(false)
        model.evaluateLaunchNudgeIfEnabled()
        XCTAssertEqual(openCount, 0, "a disabled feature must never run the launch nudge")
    }
}
