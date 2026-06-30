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
}
