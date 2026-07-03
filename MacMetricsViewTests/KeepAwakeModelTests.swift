import XCTest
import Combine
@testable import MacMetricsView

/// Direct tests for `KeepAwakeModel` (feature `keep-awake-toggle`). Exercises the model
/// with a fake assertion service so no real IOKit power assertion is created, and proves
/// the churn-isolation contract shared by every Utilities/pillar model.
@MainActor
final class KeepAwakeModelTests: XCTestCase {
    private final class FakeSleepAssertionService: SleepAssertionControlling {
        var activateResult = true
        private(set) var activateCalls = 0
        private(set) var deactivateCalls = 0
        /// Net assertions held (activate successes minus releases). Must never exceed 1.
        private(set) var held = 0

        func activate() -> Bool {
            activateCalls += 1
            guard activateResult else { return false }
            held += 1
            return true
        }

        func deactivate() {
            deactivateCalls += 1
            if held > 0 { held -= 1 }
        }
    }

    // KAWK-01: turning on creates exactly one assertion and reports active.
    func testActivateHoldsAssertionAndReportsActive() {
        let service = FakeSleepAssertionService()
        let model = KeepAwakeModel(service: service)

        model.setActive(true)

        XCTAssertTrue(model.isActive)
        XCTAssertEqual(service.activateCalls, 1)
        XCTAssertEqual(service.held, 1)
    }

    // KAWK-01: turning off releases the assertion.
    func testDeactivateReleasesAssertion() {
        let service = FakeSleepAssertionService()
        let model = KeepAwakeModel(service: service)
        model.setActive(true)

        model.setActive(false)

        XCTAssertFalse(model.isActive)
        XCTAssertEqual(service.deactivateCalls, 1)
        XCTAssertEqual(service.held, 0)
    }

    // KAWK-02: a refused assertion must leave the toggle off, not stuck-on.
    func testActivateFailureRevertsToOff() {
        let service = FakeSleepAssertionService()
        service.activateResult = false
        let model = KeepAwakeModel(service: service)

        model.setActive(true)

        XCTAssertFalse(model.isActive, "a refused assertion must not report active")
        XCTAssertEqual(service.held, 0)
    }

    // KAWK-03: never persisted — a fresh model is always off.
    func testStartsInactive() {
        XCTAssertFalse(KeepAwakeModel(service: FakeSleepAssertionService()).isActive)
    }

    // KAWK-04: redundant calls are no-ops; at most one assertion exists at any time.
    func testIdempotentActivateHoldsSingleAssertion() {
        let service = FakeSleepAssertionService()
        let model = KeepAwakeModel(service: service)

        model.setActive(true)
        model.setActive(true)
        model.toggle() // now false
        model.setActive(false)

        XCTAssertEqual(service.activateCalls, 1, "second activate is a no-op")
        XCTAssertEqual(service.deactivateCalls, 1, "second deactivate is a no-op")
        XCTAssertLessThanOrEqual(service.held, 1)
        XCTAssertFalse(model.isActive)
    }

    // Pillar contract: mutating keep-awake must not invalidate CPUState's own
    // objectWillChange — ActionsTab observes `keepAwake` directly.
    func testChurnIsolation_KeepAwakeMutationDoesNotEmitCPUStateObjectWillChange() {
        let defaults = UserDefaults(suiteName: "KeepAwakeModelTests.\(UUID().uuidString)")!
        let state = CPUState(userDefaults: defaults, sleepAssertionService: FakeSleepAssertionService())
        var fired = false
        let cancellable = state.objectWillChange.sink { fired = true }

        state.keepAwake.setActive(true)

        XCTAssertFalse(fired, "keep-awake mutation must invalidate only KeepAwakeModel")
        cancellable.cancel()
    }
}
