import XCTest
@testable import MacMetricsView

final class CleaningLockCountdownFormatterTests: XCTestCase {

    // MARK: - Below 60 s  →  "Xs"

    func testSingleDigitSeconds() {
        XCTAssertEqual(fmt(remaining: 5, total: 30), "5s")
    }

    func testDoubleDigitSeconds() {
        XCTAssertEqual(fmt(remaining: 59, total: 60), "59s")
    }

    func testOneSecondRemaining() {
        XCTAssertEqual(fmt(remaining: 1, total: 30), "1s")
    }

    func testZeroRemainingShowsZero() {
        XCTAssertEqual(fmt(remaining: 0, total: 30), "0s")
    }

    // MARK: - 60 s and above  →  "m:ss"

    func testExactlyOneMinute() {
        XCTAssertEqual(fmt(remaining: 60, total: 60), "1:00")
    }

    func testNinetySeconds() {
        XCTAssertEqual(fmt(remaining: 90, total: 120), "1:30")
    }

    func testTwoMinutes() {
        XCTAssertEqual(fmt(remaining: 120, total: 120), "2:00")
    }

    func testFiveMinutes() {
        XCTAssertEqual(fmt(remaining: 300, total: 300), "5:00")
    }

    func testSecondsColumnPaddedWithZero() {
        XCTAssertEqual(fmt(remaining: 65, total: 120), "1:05")
    }

    // MARK: - Defensive clamping

    func testNegativeRemainingClampedToZero() {
        XCTAssertEqual(fmt(remaining: -1, total: 30), "0s")
    }

    func testRemainingAboveTotalClampedToTotal() {
        // total = 30, remaining = 999 → clamped to 30 → "30s"
        XCTAssertEqual(fmt(remaining: 999, total: 30), "30s")
    }

    func testRemainingAboveTotalIn60sRange() {
        // total = 90, remaining = 200 → clamped to 90 → "1:30"
        XCTAssertEqual(fmt(remaining: 200, total: 90), "1:30")
    }

    func testNegativeTotalTreatedAsZero() {
        // total < 0 → safeTotal = 0, clamped remaining = 0
        XCTAssertEqual(fmt(remaining: 10, total: -5), "0s")
    }

    // MARK: - Fractional seconds round up

    func testFractionalSecondsRoundUp() {
        // 4.1 → rounds up to 5
        XCTAssertEqual(fmt(remaining: 4.1, total: 30), "5s")
    }

    func testFractionalSecondsAtBoundary() {
        // 59.9 → rounds up to 60 → "1:00"
        XCTAssertEqual(fmt(remaining: 59.9, total: 120), "1:00")
    }

    // MARK: - Helper

    private func fmt(remaining: TimeInterval, total: TimeInterval) -> String {
        CleaningLockCountdownFormatter.string(forRemaining: remaining, total: total)
    }
}
