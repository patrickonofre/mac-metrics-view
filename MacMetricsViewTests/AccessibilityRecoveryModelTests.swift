import XCTest
@testable import MacMetricsView

/// Direct tests for `AccessibilityRecoveryModel` extracted from `CPUState` (task-004).
/// Exercises the model standalone (no `CPUState`/`CleaningLockModel`). Reuses
/// `FakeAccessibilityAuthorization` (`CleaningLockStateTests.swift`) and
/// `FakeAccessibilityProbe` (`AccessibilityProbeTests.swift`).
@MainActor
final class AccessibilityRecoveryModelTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "AccessibilityRecoveryModelTests.\(UUID().uuidString)")!
    }

    private func makeModel(
        isTrusted: Bool = false,
        probeResult: Bool = false,
        userDefaults: UserDefaults? = nil,
        currentAppVersion: String = "2.0.0"
    ) -> (AccessibilityRecoveryModel, FakeAccessibilityProbe) {
        let probe = FakeAccessibilityProbe(result: probeResult)
        let model = AccessibilityRecoveryModel(
            userDefaults: userDefaults ?? makeDefaults(),
            authorization: FakeAccessibilityAuthorization(isTrusted: isTrusted),
            probe: probe,
            currentAppVersion: currentAppVersion
        )
        return (model, probe)
    }

    func testInitialPhaseIsIdle() {
        let (model, _) = makeModel()
        XCTAssertEqual(model.phase, .idle)
    }

    // Passive-init contract (CLNGT-01): construction alone must not touch AX state.
    func testInitDoesNotEvaluateAuthorization() {
        let (model, _) = makeModel(isTrusted: true)
        XCTAssertFalse(model.isGranted, "isGranted must stay at its default until refreshAuthorization() is called")
    }

    // Passive-init contract (CLNGT-01): construction alone must not write the grant tracker.
    func testInitDoesNotWriteGrantTracker() {
        let defaults = makeDefaults()
        _ = AccessibilityRecoveryModel(
            userDefaults: defaults,
            authorization: FakeAccessibilityAuthorization(isTrusted: true),
            probe: FakeAccessibilityProbe(),
            currentAppVersion: "2.0.0"
        )

        let tracker = AccessibilityGrantTracker.load(from: defaults)

        XCTAssertNil(tracker.lastGrantedVersion, "init must not persist a grant-tracker write")
        XCTAssertNil(tracker.lastSeenVersion, "init must not persist a grant-tracker write")
    }

    func testGrantedAtLaunchPublishesIsGranted() {
        let (model, _) = makeModel(isTrusted: true)
        model.refreshAuthorization()
        XCTAssertTrue(model.isGranted)
        XCTAssertFalse(model.resetByUpdate)
    }

    func testBeginRecoveryTransitionsToAwaitingGrant() {
        let (model, _) = makeModel()
        model.beginRecovery()
        XCTAssertEqual(model.phase, .awaitingGrant)
    }

    func testCancelRecoveryReturnsToIdle() {
        let (model, _) = makeModel()
        model.beginRecovery()
        model.cancelRecovery()
        XCTAssertEqual(model.phase, .idle)
    }

    func testPollRecoveryTrustedTransitionsToApplyingAndFiresRelaunch() {
        let (model, _) = makeModel(probeResult: true)
        var relaunched = false
        model.onRelaunch = { relaunched = true }

        model.beginRecovery()
        model.pollRecovery()

        XCTAssertEqual(model.phase, .applying)
        XCTAssertTrue(relaunched)
    }

    func testPollRecoveryUntrustedStaysAwaitingGrant() {
        let (model, _) = makeModel(probeResult: false)
        model.beginRecovery()
        model.pollRecovery()
        XCTAssertEqual(model.phase, .awaitingGrant)
    }

    func testPollRecoveryOutsideAwaitingGrantIsNoOp() {
        let (model, probe) = makeModel(probeResult: true)
        model.pollRecovery()   // still .idle
        XCTAssertEqual(probe.probeCallCount, 0)
    }

    func testResetByUpdateDetectedAcrossRelaunchWithNewVersion() {
        let defaults = makeDefaults()
        // First launch: granted on v1.0.0. `refreshAuthorization()` stands in for the
        // owner (`CleaningLockModel`) driving the first evaluation when enabled.
        let firstLaunch = AccessibilityRecoveryModel(
            userDefaults: defaults,
            authorization: FakeAccessibilityAuthorization(isTrusted: true),
            probe: FakeAccessibilityProbe(),
            currentAppVersion: "1.0.0"
        )
        firstLaunch.refreshAuthorization()
        // Relaunch on v2.0.0 with the grant reset (ad-hoc signing, TD-010).
        let afterUpdate = AccessibilityRecoveryModel(
            userDefaults: defaults,
            authorization: FakeAccessibilityAuthorization(isTrusted: false),
            probe: FakeAccessibilityProbe(),
            currentAppVersion: "2.0.0"
        )
        afterUpdate.refreshAuthorization()
        XCTAssertFalse(afterUpdate.isGranted)
        XCTAssertTrue(afterUpdate.resetByUpdate)
    }

    func testEvaluateLaunchNudgeFiresOnceForAResetVersion() {
        let defaults = makeDefaults()
        let firstLaunch = AccessibilityRecoveryModel(
            userDefaults: defaults,
            authorization: FakeAccessibilityAuthorization(isTrusted: true),
            probe: FakeAccessibilityProbe(),
            currentAppVersion: "1.0.0"
        )
        firstLaunch.refreshAuthorization()
        let afterUpdate = AccessibilityRecoveryModel(
            userDefaults: defaults,
            authorization: FakeAccessibilityAuthorization(isTrusted: false),
            probe: FakeAccessibilityProbe(),
            currentAppVersion: "2.0.0"
        )
        afterUpdate.refreshAuthorization()
        var openCount = 0
        afterUpdate.onRequestOpenPopover = { openCount += 1 }

        afterUpdate.evaluateLaunchNudge()
        afterUpdate.evaluateLaunchNudge()   // second call: already recorded, no-op

        XCTAssertEqual(openCount, 1)
    }
}
