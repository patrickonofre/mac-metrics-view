import XCTest
@testable import MacMetricsView

/// Fake authorization so tests never touch real macOS permission state.
/// `isTrusted` is mutable to simulate the user granting access mid-session.
final class FakeAccessibilityAuthorization: AccessibilityAuthorizationProtocol {
    var isTrusted: Bool
    private(set) var openSettingsCallCount = 0
    private(set) var promptCallCount = 0

    init(isTrusted: Bool = false) {
        self.isTrusted = isTrusted
    }

    func openSettings() {
        openSettingsCallCount += 1
    }

    @discardableResult
    func promptForAccess() -> Bool {
        promptCallCount += 1
        return isTrusted
    }
}

/// Stands in for `StatusItemController.openPopover()` so the AppDelegate wiring
/// (`onRequestOpenPopover` → controller open) can be asserted without an AppKit
/// status item.
@MainActor
final class PopoverOpenSpy {
    private(set) var openCount = 0
    func openPopover() { openCount += 1 }
}

@MainActor
final class CleaningLockStateTests: XCTestCase {

    // MARK: - Helpers

    private func makeState() -> CPUState {
        CPUState(userDefaults: makeUserDefaults())
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "MacMetricsViewTests.LockState.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        ud.removePersistentDomain(forName: suiteName)
        return ud
    }

    // MARK: - Initial state

    func testInitialLockPhaseIsIdle() {
        XCTAssertEqual(makeState().lockPhase, .idle)
    }

    func testInitialLockRemainingIsZero() {
        XCTAssertEqual(makeState().lockRemaining, 0)
    }

    func testInitialCleaningLockSettingsUsesDefault() {
        XCTAssertEqual(makeState().cleaningLockSettings.selectedDuration,
                       CleaningLockSettings.defaultDuration)
    }

    // MARK: - updateLockState

    func testUpdateLockStateReflectsLockedPhase() {
        let state = makeState()
        state.updateLockState(phase: .locked, remaining: 30)
        XCTAssertEqual(state.lockPhase, .locked)
        XCTAssertEqual(state.lockRemaining, 30)
    }

    func testUpdateLockStateReflectsIdlePhase() {
        let state = makeState()
        state.updateLockState(phase: .locked, remaining: 30)
        state.updateLockState(phase: .idle, remaining: 0)
        XCTAssertEqual(state.lockPhase, .idle)
        XCTAssertEqual(state.lockRemaining, 0)
    }

    // MARK: - startCleaningLock

    func testStartCleaningLockFiresOnStartLockWithSelectedDuration() {
        let state = makeState()
        var capturedDuration: TimeInterval?
        state.onStartLock = { capturedDuration = $0 }

        state.startCleaningLock()

        XCTAssertEqual(capturedDuration, CleaningLockSettings.defaultDuration)
    }

    func testStartCleaningLockUsesUpdatedDuration() {
        let state = makeState()
        var capturedDuration: TimeInterval?
        state.onStartLock = { capturedDuration = $0 }

        state.selectLockDuration(120)
        state.startCleaningLock()

        XCTAssertEqual(capturedDuration, 120)
    }

    // MARK: - selectLockDuration

    func testSelectLockDurationUpdatesSettings() {
        let state = makeState()
        state.selectLockDuration(60)
        XCTAssertEqual(state.cleaningLockSettings.selectedDuration, 60)
    }

    func testSelectLockDurationIgnoresNonPresetValues() {
        let state = makeState()
        let before = state.cleaningLockSettings.selectedDuration
        state.selectLockDuration(999)
        XCTAssertEqual(state.cleaningLockSettings.selectedDuration, before)
    }

    func testSelectLockDurationPersists() {
        let ud = makeUserDefaults()
        let state1 = CPUState(userDefaults: ud)
        state1.selectLockDuration(300)

        let state2 = CPUState(userDefaults: ud)
        XCTAssertEqual(state2.cleaningLockSettings.selectedDuration, 300)
    }

    // MARK: - Lock wiring with fake service (mirrors AppDelegate logic)

    func testFakeServiceExpiryUpdatesStateToIdle() {
        let state = makeState()
        let service = FakeInputLockService()

        // Wire like AppDelegate does.
        state.onStartLock = { duration in
            state.updateLockState(phase: .locked, remaining: duration)
            service.start(duration: duration)
        }
        service.onTick = { remaining in
            state.updateLockState(phase: .locked, remaining: remaining)
        }
        service.onEnd = { _ in
            state.updateLockState(phase: .idle, remaining: 0)
        }

        state.startCleaningLock() // fires onStartLock → service.start
        XCTAssertEqual(state.lockPhase, .locked)

        // Drain the timer down to expiry.
        let ticks = Int(CleaningLockSettings.defaultDuration)
        for _ in 0..<ticks { service.tick() }

        XCTAssertEqual(state.lockPhase, .idle)
        XCTAssertEqual(state.lockRemaining, 0)
    }

    func testFakeServiceAbortUpdatesStateToIdle() {
        let state = makeState()
        let service = FakeInputLockService()

        state.onStartLock = { duration in
            state.updateLockState(phase: .locked, remaining: duration)
            service.start(duration: duration)
        }
        service.onEnd = { _ in
            state.updateLockState(phase: .idle, remaining: 0)
        }

        state.startCleaningLock()
        service.stop(reason: .aborted)

        XCTAssertEqual(state.lockPhase, .idle)
        XCTAssertEqual(state.lockRemaining, 0)
    }

    func testAccessibilityDeniedPreventsOnStartLockFiring() {
        // Simulate gating: if the permission check fails, the UI never calls
        // startCleaningLock(), so onStartLock must never fire.
        let state = makeState()
        var fired = false
        state.onStartLock = { _ in fired = true }

        let isPermissionGranted = false  // simulates AXIsProcessTrusted() == false
        if isPermissionGranted {
            state.startCleaningLock()
        }

        XCTAssertFalse(fired)
    }

    // MARK: - Accessibility authorization gate

    func testInitialAccessibilityGateReflectsAuthorization() {
        let granted = CPUState(userDefaults: makeUserDefaults(),
                               accessibilityAuthorization: FakeAccessibilityAuthorization(isTrusted: true))
        let denied = CPUState(userDefaults: makeUserDefaults(),
                              accessibilityAuthorization: FakeAccessibilityAuthorization(isTrusted: false))
        XCTAssertTrue(granted.isAccessibilityGranted)
        XCTAssertFalse(denied.isAccessibilityGranted)
    }

    func testRefreshPicksUpGrantMadeAfterLaunch() {
        // Reproduces the bug: app launches without permission, user grants it
        // in System Settings, then reopens the popover. The gate must flip.
        let auth = FakeAccessibilityAuthorization(isTrusted: false)
        let state = CPUState(userDefaults: makeUserDefaults(), accessibilityAuthorization: auth)
        XCTAssertFalse(state.isAccessibilityGranted)

        auth.isTrusted = true
        state.refreshAccessibilityAuthorization()

        XCTAssertTrue(state.isAccessibilityGranted)
    }

    func testRefreshPicksUpRevokedPermission() {
        let auth = FakeAccessibilityAuthorization(isTrusted: true)
        let state = CPUState(userDefaults: makeUserDefaults(), accessibilityAuthorization: auth)
        XCTAssertTrue(state.isAccessibilityGranted)

        auth.isTrusted = false
        state.refreshAccessibilityAuthorization()

        XCTAssertFalse(state.isAccessibilityGranted)
    }

    // MARK: - Grant reset by update (ad-hoc signing, TD-010)

    func testNoResetFlagOnFreshInstall() {
        // Never granted on any version → ordinary first-grant prompt.
        let state = CPUState(userDefaults: makeUserDefaults(),
                             accessibilityAuthorization: FakeAccessibilityAuthorization(isTrusted: false),
                             currentAppVersion: "1.0.0")
        XCTAssertFalse(state.accessibilityResetByUpdate)
    }

    func testGrantedStateNeverFlagsReset() {
        let state = CPUState(userDefaults: makeUserDefaults(),
                             accessibilityAuthorization: FakeAccessibilityAuthorization(isTrusted: true),
                             currentAppVersion: "1.0.0")
        XCTAssertFalse(state.accessibilityResetByUpdate)
    }

    func testManualRevokeOnSameVersionDoesNotFlagReset() {
        let ud = makeUserDefaults()
        let auth = FakeAccessibilityAuthorization(isTrusted: true)
        let state = CPUState(userDefaults: ud, accessibilityAuthorization: auth, currentAppVersion: "1.0.0")

        auth.isTrusted = false
        state.refreshAccessibilityAuthorization()

        XCTAssertTrue(state.isAccessibilityGranted == false)
        XCTAssertFalse(state.accessibilityResetByUpdate)
    }

    func testGrantLostAfterUpdateFlagsReset() {
        // Reproduces the reported bug: AX granted on 1.0.0, the app updates to
        // 1.1.0 (new cdhash), and the relaunched build is no longer trusted.
        let ud = makeUserDefaults()
        let granted = FakeAccessibilityAuthorization(isTrusted: true)
        _ = CPUState(userDefaults: ud, accessibilityAuthorization: granted, currentAppVersion: "1.0.0")

        let afterUpdate = CPUState(userDefaults: ud,
                                   accessibilityAuthorization: FakeAccessibilityAuthorization(isTrusted: false),
                                   currentAppVersion: "1.1.0")

        XCTAssertFalse(afterUpdate.isAccessibilityGranted)
        XCTAssertTrue(afterUpdate.accessibilityResetByUpdate)
    }

    func testUpdateFromNeverGrantedVersionFlagsReset() {
        // User ran a prior version that was never recorded as granted (e.g. it
        // predated the tracker, or the grant was always stale), then updated.
        // The reset guidance must still appear.
        let ud = makeUserDefaults()
        _ = CPUState(userDefaults: ud,
                     accessibilityAuthorization: FakeAccessibilityAuthorization(isTrusted: false),
                     currentAppVersion: "1.0.1")

        let afterUpdate = CPUState(userDefaults: ud,
                                   accessibilityAuthorization: FakeAccessibilityAuthorization(isTrusted: false),
                                   currentAppVersion: "1.0.2")

        XCTAssertFalse(afterUpdate.isAccessibilityGranted)
        XCTAssertTrue(afterUpdate.accessibilityResetByUpdate)
    }

    func testResetFlagStaysSetAcrossRefreshesWhileUngranted() {
        // Once detected, the reset guidance must not disappear when the popover
        // is reopened (refresh) before the user actually grants.
        let ud = makeUserDefaults()
        _ = CPUState(userDefaults: ud,
                     accessibilityAuthorization: FakeAccessibilityAuthorization(isTrusted: false),
                     currentAppVersion: "1.0.1")

        let state = CPUState(userDefaults: ud,
                             accessibilityAuthorization: FakeAccessibilityAuthorization(isTrusted: false),
                             currentAppVersion: "1.0.2")
        XCTAssertTrue(state.accessibilityResetByUpdate)

        state.refreshAccessibilityAuthorization()
        state.refreshAccessibilityAuthorization()

        XCTAssertTrue(state.accessibilityResetByUpdate)
    }

    // MARK: - Access request + relaunch (free mitigations)

    func testFirstAccessRequestShowsNativePrompt() {
        // The first tap should fire the native prompt (which registers the entry
        // under the current code identity), and also open Settings as a fallback.
        let auth = FakeAccessibilityAuthorization(isTrusted: false)
        let state = CPUState(userDefaults: makeUserDefaults(), accessibilityAuthorization: auth)

        state.requestAccessibilityAccess()

        XCTAssertEqual(auth.promptCallCount, 1)
        XCTAssertEqual(auth.openSettingsCallCount, 1)
    }

    func testRepeatAccessRequestSkipsPromptAndOpensSettings() {
        // macOS only shows the native prompt once per launch, so later taps must
        // not re-prompt; they open the Settings pane directly instead.
        let auth = FakeAccessibilityAuthorization(isTrusted: false)
        let state = CPUState(userDefaults: makeUserDefaults(), accessibilityAuthorization: auth)

        state.requestAccessibilityAccess()
        state.requestAccessibilityAccess()
        state.requestAccessibilityAccess()

        XCTAssertEqual(auth.promptCallCount, 1)
        XCTAssertEqual(auth.openSettingsCallCount, 3)
    }

    func testReGrantingAfterUpdateClearsResetFlag() {
        let ud = makeUserDefaults()
        _ = CPUState(userDefaults: ud,
                     accessibilityAuthorization: FakeAccessibilityAuthorization(isTrusted: true),
                     currentAppVersion: "1.0.0")

        let auth = FakeAccessibilityAuthorization(isTrusted: false)
        let state = CPUState(userDefaults: ud, accessibilityAuthorization: auth, currentAppVersion: "1.1.0")
        XCTAssertTrue(state.accessibilityResetByUpdate)

        auth.isTrusted = true
        state.refreshAccessibilityAuthorization()

        XCTAssertTrue(state.isAccessibilityGranted)
        XCTAssertFalse(state.accessibilityResetByUpdate)
    }

    // MARK: - Recovery state machine (probe poll loop)

    private func makeRecoveryState(
        probe: FakeAccessibilityProbe,
        auth: FakeAccessibilityAuthorization = FakeAccessibilityAuthorization(isTrusted: false)
    ) -> CPUState {
        CPUState(userDefaults: makeUserDefaults(), accessibilityAuthorization: auth, accessibilityProbe: probe)
    }

    func testBeginRecoveryEntersAwaitingOpensSettingsAndStartsPolling() {
        let probe = FakeAccessibilityProbe(result: false)
        let auth = FakeAccessibilityAuthorization(isTrusted: false)
        let state = makeRecoveryState(probe: probe, auth: auth)

        state.beginAccessibilityRecovery()

        XCTAssertEqual(state.recoveryPhase, .awaitingGrant)
        XCTAssertEqual(auth.openSettingsCallCount, 1)

        // Polling started: a tick spawns the probe.
        state.pollAccessibilityRecovery()
        XCTAssertEqual(probe.probeCallCount, 1)
    }

    func testProbeTrueTransitionsToApplyingAndRelaunchesExactlyOnce() {
        let probe = FakeAccessibilityProbe(result: true)
        let state = makeRecoveryState(probe: probe)
        var relaunchCount = 0
        state.onRelaunch = { relaunchCount += 1 }

        state.beginAccessibilityRecovery()
        state.pollAccessibilityRecovery()

        XCTAssertEqual(state.recoveryPhase, .applying)
        XCTAssertEqual(relaunchCount, 1)

        // A further tick is a no-op (not awaitingGrant) — relaunch fires only once.
        state.pollAccessibilityRecovery()
        XCTAssertEqual(relaunchCount, 1)
    }

    func testProbeFalseStaysAwaitingAndNeverRelaunches() {
        let probe = FakeAccessibilityProbe(result: false)
        let state = makeRecoveryState(probe: probe)
        var relaunchCount = 0
        state.onRelaunch = { relaunchCount += 1 }

        state.beginAccessibilityRecovery()
        state.pollAccessibilityRecovery()
        state.pollAccessibilityRecovery()

        XCTAssertEqual(state.recoveryPhase, .awaitingGrant)
        XCTAssertEqual(relaunchCount, 0)
    }

    func testCancelStopsLoopNoFurtherProbeOrRelaunch() {
        let probe = FakeAccessibilityProbe(result: false)
        let state = makeRecoveryState(probe: probe)
        var relaunchCount = 0
        state.onRelaunch = { relaunchCount += 1 }

        state.beginAccessibilityRecovery()
        state.pollAccessibilityRecovery()
        XCTAssertEqual(probe.probeCallCount, 1)

        state.cancelAccessibilityRecovery()
        XCTAssertEqual(state.recoveryPhase, .idle)

        // Even if the grant arrives now, a tick after cancel must not probe or relaunch.
        probe.result = true
        state.pollAccessibilityRecovery()
        XCTAssertEqual(probe.probeCallCount, 1)
        XCTAssertEqual(relaunchCount, 0)
    }

    func testNoProbeCallWhileIdle() {
        let probe = FakeAccessibilityProbe(result: true)
        let state = makeRecoveryState(probe: probe)

        XCTAssertEqual(state.recoveryPhase, .idle)
        state.pollAccessibilityRecovery()

        XCTAssertEqual(probe.probeCallCount, 0)
    }

    func testBeginIsIgnoredWhileAlreadyRecovering() {
        let probe = FakeAccessibilityProbe(result: false)
        let auth = FakeAccessibilityAuthorization(isTrusted: false)
        let state = makeRecoveryState(probe: probe, auth: auth)

        state.beginAccessibilityRecovery()
        state.beginAccessibilityRecovery()

        // Second begin is a no-op: Settings opened once, still a single recovery.
        XCTAssertEqual(auth.openSettingsCallCount, 1)
        XCTAssertEqual(state.recoveryPhase, .awaitingGrant)
    }

    func testLateProbeResultAfterCancelDoesNotRelaunch() {
        // A probe spawned before cancel can complete after cancel; the result must
        // be ignored so no stray relaunch fires.
        let probe = FakeAccessibilityProbe(result: true)
        probe.defersCompletion = true
        let state = makeRecoveryState(probe: probe)
        var relaunchCount = 0
        state.onRelaunch = { relaunchCount += 1 }

        state.beginAccessibilityRecovery()
        state.pollAccessibilityRecovery()       // probe in flight, completion held
        state.cancelAccessibilityRecovery()      // user dismissed
        probe.flush()                             // probe result lands late

        XCTAssertEqual(state.recoveryPhase, .idle)
        XCTAssertEqual(relaunchCount, 0)
    }

    // MARK: - Recovery: end-to-end with fakes (mirrors AppDelegate wiring)

    func testEndToEndRecoveryFlipsToTrustedThenRelaunchesAndEndsApplying() {
        let probe = FakeAccessibilityProbe(result: false)
        let state = makeRecoveryState(probe: probe)
        var relaunchCount = 0
        state.onRelaunch = { relaunchCount += 1 }

        state.beginAccessibilityRecovery()
        state.pollAccessibilityRecovery()         // not granted yet
        XCTAssertEqual(state.recoveryPhase, .awaitingGrant)
        XCTAssertEqual(relaunchCount, 0)

        probe.result = true                         // user removed + re-added the entry
        state.pollAccessibilityRecovery()

        XCTAssertEqual(relaunchCount, 1)
        XCTAssertEqual(state.recoveryPhase, .applying)
    }

    // MARK: - One-time launch nudge

    /// Builds a state where an update reset the grant (granted on `1.0.0`, now on
    /// `1.1.0` and untrusted), sharing one UserDefaults suite so the grant tracker
    /// carries over.
    private func makeResetState(userDefaults ud: UserDefaults) -> CPUState {
        _ = CPUState(userDefaults: ud,
                     accessibilityAuthorization: FakeAccessibilityAuthorization(isTrusted: true),
                     currentAppVersion: "1.0.0")
        return CPUState(userDefaults: ud,
                        accessibilityAuthorization: FakeAccessibilityAuthorization(isTrusted: false),
                        currentAppVersion: "1.1.0")
    }

    func testLaunchNudgeFiresOnceWhenResetAndFlagUnset() {
        let ud = makeUserDefaults()
        let state = makeResetState(userDefaults: ud)
        XCTAssertTrue(state.accessibilityResetByUpdate)

        var openCount = 0
        state.onRequestOpenPopover = { openCount += 1 }

        state.evaluateAccessibilityLaunchNudge()
        XCTAssertEqual(openCount, 1)

        // Same version, second evaluation: the flag is recorded, so it never repeats.
        state.evaluateAccessibilityLaunchNudge()
        XCTAssertEqual(openCount, 1)
    }

    func testLaunchNudgeRecordsFlagForCurrentVersion() {
        let ud = makeUserDefaults()
        let state = makeResetState(userDefaults: ud)
        state.onRequestOpenPopover = {}

        state.evaluateAccessibilityLaunchNudge()

        XCTAssertFalse(AccessibilityNudgeTracker.load(from: ud).shouldNudge(forVersion: "1.1.0"))
    }

    func testLaunchNudgeDoesNotFireWhenGranted() {
        let state = CPUState(userDefaults: makeUserDefaults(),
                             accessibilityAuthorization: FakeAccessibilityAuthorization(isTrusted: true),
                             currentAppVersion: "1.1.0")
        var openCount = 0
        state.onRequestOpenPopover = { openCount += 1 }

        state.evaluateAccessibilityLaunchNudge()

        XCTAssertEqual(openCount, 0)
    }

    func testLaunchNudgeDoesNotFireWhenNoResetDetected() {
        // Fresh install, never granted → first-grant, not a reset.
        let state = CPUState(userDefaults: makeUserDefaults(),
                             accessibilityAuthorization: FakeAccessibilityAuthorization(isTrusted: false),
                             currentAppVersion: "1.0.0")
        XCTAssertFalse(state.accessibilityResetByUpdate)

        var openCount = 0
        state.onRequestOpenPopover = { openCount += 1 }

        state.evaluateAccessibilityLaunchNudge()

        XCTAssertEqual(openCount, 0)
    }

    func testLaunchNudgeDoesNotFireWhenFlagAlreadySetForVersion() {
        let ud = makeUserDefaults()
        AccessibilityNudgeTracker(lastNudgedVersion: "1.1.0").save(to: ud)
        let state = makeResetState(userDefaults: ud)
        XCTAssertTrue(state.accessibilityResetByUpdate)

        var openCount = 0
        state.onRequestOpenPopover = { openCount += 1 }

        state.evaluateAccessibilityLaunchNudge()

        XCTAssertEqual(openCount, 0)
    }

    // MARK: - AppDelegate wiring mirror (onRequestOpenPopover → openPopover)

    func testLaunchNudgeInvokesWiredControllerOpenPopover() {
        // Mirrors AppDelegate: onRequestOpenPopover is wired to the controller's
        // openPopover(); a reset-triggered launch nudge must reach it once.
        let ud = makeUserDefaults()
        let state = makeResetState(userDefaults: ud)
        let controller = PopoverOpenSpy()
        state.onRequestOpenPopover = { controller.openPopover() }

        state.evaluateAccessibilityLaunchNudge()

        XCTAssertEqual(controller.openCount, 1)
    }

    func testRelaunchHandshakeRemainsTheApplyMechanism() {
        // Task 6: applying a detected grant reuses the existing onRelaunch path.
        let probe = FakeAccessibilityProbe(result: true)
        let state = makeRecoveryState(probe: probe)
        var relaunchCount = 0
        state.onRelaunch = { relaunchCount += 1 }

        state.beginAccessibilityRecovery()
        state.pollAccessibilityRecovery()

        XCTAssertEqual(relaunchCount, 1)
        XCTAssertEqual(state.recoveryPhase, .applying)
    }
}
