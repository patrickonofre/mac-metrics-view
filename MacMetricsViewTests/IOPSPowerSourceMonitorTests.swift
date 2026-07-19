import XCTest
@testable import MacMetricsView

/// Tests for `IOPSPowerSourceMonitor`'s pure sample→snapshot mapping (feature
/// `lid-close-keep-awake`, LIDC-14 data feed). The adapter glue (start/stop/delegate)
/// is thin OS-boundary code covered by the build gate, per the coverage matrix.
@MainActor
final class IOPSPowerSourceMonitorTests: XCTestCase {

    private func sample(charge: Int?, source: BatteryPowerSource) -> BatterySample {
        BatterySample(
            chargePercent: charge,
            powerSource: source,
            isCharging: false,
            timeRemaining: nil,
            healthCondition: .normal,
            cycleCount: nil
        )
    }

    // LIDC-14: a battery-power reading maps level + isOnBattery=true.
    func testMapsBatteryReadingToSnapshot() {
        let snapshot = IOPSPowerSourceMonitor.snapshot(from: sample(charge: 42, source: .battery))

        XCTAssertEqual(snapshot, PowerSourceSnapshot(levelPercent: 42, isOnBattery: true))
    }

    // LIDC-14: an AC reading maps isOnBattery=false so the policy never blocks on AC.
    func testMapsACReadingToSnapshot() {
        let snapshot = IOPSPowerSourceMonitor.snapshot(from: sample(charge: 9, source: .ac))

        XCTAssertEqual(snapshot, PowerSourceSnapshot(levelPercent: 9, isOnBattery: false))
    }

    // Unreadable charge percent drops the reading — the fail-safe must never act on a
    // fabricated level.
    func testUnreadableChargeProducesNoSnapshot() {
        XCTAssertNil(IOPSPowerSourceMonitor.snapshot(from: sample(charge: nil, source: .battery)))
    }
}
