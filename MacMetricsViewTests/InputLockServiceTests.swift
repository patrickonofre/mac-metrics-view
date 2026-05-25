import XCTest
@testable import MacMetricsView

// MARK: - Fake InputLockService

/// Fake that exercises the protocol contract without touching CGEventTap.
@MainActor
final class FakeInputLockService: InputLockServiceProtocol {
    private(set) var phase: LockPhase = .idle
    private(set) var remaining: TimeInterval = 0
    var onTick: ((TimeInterval) -> Void)?
    var onEnd: ((LockEndReason) -> Void)?

    /// Simulated clock ticks; each call decrements `remaining` by 1.
    func tick() {
        guard phase == .locked else { return }
        remaining = max(0, remaining - 1)
        onTick?(remaining)
        if remaining <= 0 {
            endSession(reason: .expired)
        }
    }

    /// Simulate the system disabling the tap (no-op in fake; real impl re-enables).
    var tapDisabledByTimeoutCallCount = 0
    func simulateTapDisabledByTimeout() {
        tapDisabledByTimeoutCallCount += 1
        // The real implementation re-enables; the fake just counts the call.
    }

    func start(duration: TimeInterval) {
        guard phase == .idle, duration > 0 else { return }
        sessionDuration = duration
        remaining = duration
        phase = .locked
    }

    func stop(reason: LockEndReason) {
        guard phase == .locked else { return }
        endSession(reason: reason)
    }

    // MARK: - Private

    private var sessionDuration: TimeInterval = 0

    private func endSession(reason: LockEndReason) {
        phase = .idle
        remaining = 0
        onEnd?(reason)
    }
}

// MARK: - Tests

@MainActor
final class InputLockServiceTests: XCTestCase {

    // MARK: - start / idle transitions

    func testStartMovesToLockedPhase() {
        let service = FakeInputLockService()
        service.start(duration: 30)
        XCTAssertEqual(service.phase, .locked)
    }

    func testStartSetsRemainingToDuration() {
        let service = FakeInputLockService()
        service.start(duration: 60)
        XCTAssertEqual(service.remaining, 60)
    }

    func testStartIsIdempotentWhenAlreadyLocked() {
        let service = FakeInputLockService()
        service.start(duration: 30)
        service.start(duration: 999) // second call ignored
        XCTAssertEqual(service.remaining, 30)
    }

    func testStartWithZeroDurationIsNoOp() {
        let service = FakeInputLockService()
        service.start(duration: 0)
        XCTAssertEqual(service.phase, .idle)
    }

    // MARK: - Countdown and expiry

    func testRemainingDecreasesEachTick() {
        let service = FakeInputLockService()
        service.start(duration: 5)
        service.tick()
        XCTAssertEqual(service.remaining, 4)
    }

    func testExpiryMovesToIdle() {
        let service = FakeInputLockService()
        service.start(duration: 3)
        service.tick(); service.tick(); service.tick()
        XCTAssertEqual(service.phase, .idle)
    }

    func testExpiryFiresOnEndWithExpiredReason() {
        let service = FakeInputLockService()
        var capturedReason: LockEndReason?
        service.onEnd = { capturedReason = $0 }
        service.start(duration: 2)
        service.tick(); service.tick()
        XCTAssertEqual(capturedReason, .expired)
    }

    func testRemainingIsZeroAfterExpiry() {
        let service = FakeInputLockService()
        service.start(duration: 1)
        service.tick()
        XCTAssertEqual(service.remaining, 0)
    }

    // MARK: - Abort

    func testStopWithAbortedReasonMovesToIdle() {
        let service = FakeInputLockService()
        service.start(duration: 30)
        service.stop(reason: .aborted)
        XCTAssertEqual(service.phase, .idle)
    }

    func testStopFiresOnEndWithAbortedReason() {
        let service = FakeInputLockService()
        var capturedReason: LockEndReason?
        service.onEnd = { capturedReason = $0 }
        service.start(duration: 30)
        service.stop(reason: .aborted)
        XCTAssertEqual(capturedReason, .aborted)
    }

    // MARK: - Terminated (failsafe)

    func testStopWithTerminatedReasonMovesToIdle() {
        let service = FakeInputLockService()
        service.start(duration: 30)
        service.stop(reason: .terminated)
        XCTAssertEqual(service.phase, .idle)
    }

    func testStopIsNoOpWhenAlreadyIdle() {
        let service = FakeInputLockService()
        var callCount = 0
        service.onEnd = { _ in callCount += 1 }
        service.stop(reason: .terminated) // already idle
        XCTAssertEqual(callCount, 0)
        XCTAssertEqual(service.phase, .idle)
    }

    // MARK: - Tap-disabled-by-timeout resilience

    func testSimulateTapDisabledByTimeoutIsTracked() {
        let service = FakeInputLockService()
        service.start(duration: 30)
        service.simulateTapDisabledByTimeout()
        // Fake just counts the call; real impl re-enables.
        XCTAssertEqual(service.tapDisabledByTimeoutCallCount, 1)
        // Session must continue after a tap-disabled event.
        XCTAssertEqual(service.phase, .locked)
    }

    // MARK: - Remaining clamping

    func testRemainingNeverGoesBelowZero() {
        let service = FakeInputLockService()
        service.start(duration: 1)
        service.tick() // expires
        service.tick() // extra tick — no-op after idle
        XCTAssertEqual(service.remaining, 0)
    }
}
