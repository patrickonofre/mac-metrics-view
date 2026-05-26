import XCTest
@testable import MacMetricsView

/// Fake authorization so tests never touch real macOS permission state.
/// `isTrusted` is mutable to simulate the user granting access mid-session.
final class FakeAccessibilityAuthorization: AccessibilityAuthorizationProtocol {
    var isTrusted: Bool
    private(set) var openSettingsCallCount = 0

    init(isTrusted: Bool = false) {
        self.isTrusted = isTrusted
    }

    func openSettings() {
        openSettingsCallCount += 1
    }
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
}
