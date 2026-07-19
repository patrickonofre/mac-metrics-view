import XCTest
@testable import MacMetricsView

/// Tests for `LidCloseFailsafePolicy` (feature `lid-close-keep-awake`, LIDC-14/16).
/// Pure boundary checks around the fixed 10% threshold.
final class LidCloseFailsafePolicyTests: XCTestCase {

    // LIDC-14: below 10% on battery power must block.
    func testBlocksAt9PercentOnBattery() {
        XCTAssertTrue(LidCloseFailsafePolicy.shouldBlock(levelPercent: 9, isOnBattery: true))
    }

    // LIDC-14 boundary: exactly 10% is NOT below the threshold — allow.
    func testAllowsAtExactly10PercentOnBattery() {
        XCTAssertFalse(LidCloseFailsafePolicy.shouldBlock(levelPercent: 10, isOnBattery: true))
    }

    // LIDC-16: on AC power the fail-safe never applies, even below threshold.
    func testAllowsAt9PercentOnAC() {
        XCTAssertFalse(LidCloseFailsafePolicy.shouldBlock(levelPercent: 9, isOnBattery: false))
    }

    // LIDC-14: healthy level on battery does not block.
    func testAllowsAtHighLevelOnBattery() {
        XCTAssertFalse(LidCloseFailsafePolicy.shouldBlock(levelPercent: 80, isOnBattery: true))
    }

    // LIDC-14 (extreme lower bound): 0% on battery blocks.
    func testBlocksAtZeroPercentOnBattery() {
        XCTAssertTrue(LidCloseFailsafePolicy.shouldBlock(levelPercent: 0, isOnBattery: true))
    }

    // Snapshot overload must agree with the primitive form (used by model wiring).
    func testSnapshotOverloadMatchesPrimitiveForm() {
        XCTAssertTrue(LidCloseFailsafePolicy.shouldBlock(PowerSourceSnapshot(levelPercent: 9, isOnBattery: true)))
        XCTAssertFalse(LidCloseFailsafePolicy.shouldBlock(PowerSourceSnapshot(levelPercent: 10, isOnBattery: true)))
        XCTAssertFalse(LidCloseFailsafePolicy.shouldBlock(PowerSourceSnapshot(levelPercent: 9, isOnBattery: false)))
    }
}
