import XCTest
@testable import MacMetricsView

@MainActor
final class MainRunLoopTimerTests: XCTestCase {

    // MARK: - nextFireDate alignment (pure, no run loop)

    func testNextFireDateSnapsToNextIntervalMultiple() {
        let anchor = Date(timeIntervalSinceReferenceDate: 0)
        // 2.3s elapsed, 1s grid -> next multiple is 3.0s after the anchor.
        let fire = MainRunLoopTimer.nextFireDate(
            interval: 1,
            anchor: anchor,
            now: anchor.addingTimeInterval(2.3)
        )
        XCTAssertEqual(fire.timeIntervalSince(anchor), 3.0, accuracy: 1e-9)
    }

    func testNextFireDateUsesIntervalGridNotNow() {
        let anchor = Date(timeIntervalSinceReferenceDate: 0)
        // 0.5s elapsed, 3s grid -> next multiple is 3.0s after the anchor.
        let fire = MainRunLoopTimer.nextFireDate(
            interval: 3,
            anchor: anchor,
            now: anchor.addingTimeInterval(0.5)
        )
        XCTAssertEqual(fire.timeIntervalSince(anchor), 3.0, accuracy: 1e-9)
    }

    func testNextFireDateIsStrictlyAfterNowOnAGridBoundary() {
        let anchor = Date(timeIntervalSinceReferenceDate: 0)
        // Exactly on the grid (3.0s) -> next fire is the following multiple (6.0s),
        // never the current instant, so a tick is not skipped or doubled.
        let fire = MainRunLoopTimer.nextFireDate(
            interval: 3,
            anchor: anchor,
            now: anchor.addingTimeInterval(3.0)
        )
        XCTAssertEqual(fire.timeIntervalSince(anchor), 6.0, accuracy: 1e-9)
    }

    func testTwoIntervalsShareTheSameGridFromOneAnchor() {
        let anchor = Date(timeIntervalSinceReferenceDate: 0)
        let now = anchor.addingTimeInterval(5.4)
        let oneSecond = MainRunLoopTimer.nextFireDate(interval: 1, anchor: anchor, now: now)
        let twoSecond = MainRunLoopTimer.nextFireDate(interval: 2, anchor: anchor, now: now)
        // 1s grid -> 6.0s; 2s grid -> 6.0s: both land on the same instant so the
        // kernel can coalesce their wakeups.
        XCTAssertEqual(oneSecond.timeIntervalSince(anchor), 6.0, accuracy: 1e-9)
        XCTAssertEqual(twoSecond.timeIntervalSince(anchor), 6.0, accuracy: 1e-9)
    }

    // MARK: - repeating() applies tolerance and aligns the timer

    func testRepeatingAppliesTolerance() {
        let timer = MainRunLoopTimer.repeating(every: 3, tolerance: 0.75) {}
        defer { timer.invalidate() }
        XCTAssertEqual(timer.tolerance, 0.75, accuracy: 1e-9)
    }

    func testRepeatingDefaultsToleranceToZero() {
        let timer = MainRunLoopTimer.repeating(every: 1) {}
        defer { timer.invalidate() }
        XCTAssertEqual(timer.tolerance, 0, accuracy: 1e-9)
    }

    func testRepeatingFireDateLandsOnTheEpochGrid() {
        let interval: TimeInterval = 2
        let timer = MainRunLoopTimer.repeating(every: interval, tolerance: 0.5) {}
        defer { timer.invalidate() }
        let offset = timer.fireDate.timeIntervalSince(MainRunLoopTimer.epoch)
        let remainder = offset.truncatingRemainder(dividingBy: interval)
        // Distance to the nearest grid multiple is ~0 (allowing for the small time
        // between epoch capture and this call).
        let distance = min(remainder, interval - remainder)
        XCTAssertLessThan(distance, 0.05)
    }

    func testRepeatingFiresActionOnMainActor() {
        let expectation = expectation(description: "timer fired")
        expectation.assertForOverFulfill = false
        let timer = MainRunLoopTimer.repeating(every: 0.05) {
            // Reaching here at all proves main-actor isolation (the closure is
            // @MainActor); fulfilling once is enough.
            expectation.fulfill()
        }
        defer { timer.invalidate() }
        wait(for: [expectation], timeout: 2.0)
    }
}
