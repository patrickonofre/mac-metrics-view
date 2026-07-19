import XCTest
@testable import MacMetricsView

/// Tests for `LidCloseHelperCore` (feature `lid-close-keep-awake`, LIDC-02/03/12).
/// The pmset seam is an injected closure recording every invocation, so daemon logic
/// runs under `swift test` with zero real `pmset` calls.
final class LidCloseHelperCoreTests: XCTestCase {

    /// Records each pmset invocation's argument; result is scriptable per call.
    private final class PmsetSpy {
        private(set) var calls: [Bool] = []
        var result = true

        func run(_ disabled: Bool) -> Bool {
            calls.append(disabled)
            return result
        }
    }

    // LIDC-02: enable runs pmset(true) exactly once and reports success.
    func testEnableRunsPmsetTrueOnceAndSucceeds() {
        let spy = PmsetSpy()
        let core = LidCloseHelperCore(runPmset: spy.run)

        XCTAssertTrue(core.setSleepDisabled(true))

        XCTAssertEqual(spy.calls, [true])
        XCTAssertTrue(core.isEnabled)
    }

    // LIDC-03: disable runs pmset(false) and reports success. Runs even when the core
    // never enabled (spec edge case: externally-set flag still gets written false).
    func testDisableRunsPmsetFalseAndSucceeds() {
        let spy = PmsetSpy()
        let core = LidCloseHelperCore(runPmset: spy.run)
        _ = core.setSleepDisabled(true)

        XCTAssertTrue(core.setSleepDisabled(false))

        XCTAssertEqual(spy.calls, [true, false])
        XCTAssertFalse(core.isEnabled)
    }

    // LIDC-12: connection loss while enabled reverts with exactly one pmset(false).
    func testConnectionLostWhileEnabledRevertsExactlyOnce() {
        let spy = PmsetSpy()
        let core = LidCloseHelperCore(runPmset: spy.run)
        _ = core.setSleepDisabled(true)

        core.connectionLost()

        XCTAssertEqual(spy.calls, [true, false], "revert must be exactly one pmset(false)")
        XCTAssertFalse(core.isEnabled)
    }

    // LIDC-12 (exactly-once): a second connection loss after the revert is a no-op.
    func testSecondConnectionLostMakesNoFurtherCalls() {
        let spy = PmsetSpy()
        let core = LidCloseHelperCore(runPmset: spy.run)
        _ = core.setSleepDisabled(true)
        core.connectionLost()

        core.connectionLost()

        XCTAssertEqual(spy.calls, [true, false], "second loss must not run pmset again")
    }

    // LIDC-12 (guard): connection loss while disabled makes zero pmset calls — never
    // touch the system flag on behalf of a client that had nothing enabled.
    func testConnectionLostWhileDisabledMakesZeroCalls() {
        let spy = PmsetSpy()
        let core = LidCloseHelperCore(runPmset: spy.run)

        core.connectionLost()

        XCTAssertTrue(spy.calls.isEmpty)
    }

    // LIDC-05 (helper side): pmset failure is reported to the caller and the core does
    // not mark itself enabled — so no phantom revert is armed.
    func testPmsetFailureReportedAndDoesNotArmState() {
        let spy = PmsetSpy()
        spy.result = false
        let core = LidCloseHelperCore(runPmset: spy.run)

        XCTAssertFalse(core.setSleepDisabled(true), "pmset failure must surface to the caller")
        XCTAssertFalse(core.isEnabled)

        // A failed enable must not arm the connection-loss revert.
        spy.result = true
        core.connectionLost()
        XCTAssertEqual(spy.calls, [true], "no revert after a failed enable")
    }
}
