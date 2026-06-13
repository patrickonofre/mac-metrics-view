import XCTest
@testable import MacMetricsView

final class BatterySampleTests: XCTestCase {
    private func make(
        chargePercent: Int?,
        timeRemaining: TimeInterval? = 3600,
        cycleCount: Int? = 100,
        isCharging: Bool = false,
        powerSource: BatteryPowerSource = .battery,
        condition: BatteryCondition = .normal
    ) -> BatterySample {
        BatterySample(
            chargePercent: chargePercent,
            powerSource: powerSource,
            isCharging: isCharging,
            timeRemaining: timeRemaining,
            healthCondition: condition,
            cycleCount: cycleCount
        )
    }

    func testChargeWithinRangeRetained() {
        XCTAssertEqual(make(chargePercent: 50).chargePercent, 50)
    }

    func testChargeOutOfRangeNormalizesToNil() {
        XCTAssertNil(make(chargePercent: 150).chargePercent)
        XCTAssertNil(make(chargePercent: -5).chargePercent)
    }

    func testNegativeTimeSentinelNormalizesToNil() {
        XCTAssertNil(make(chargePercent: 50, timeRemaining: -1).timeRemaining)
    }

    func testPositiveTimeRetained() {
        XCTAssertEqual(make(chargePercent: 50, timeRemaining: 7200).timeRemaining, 7200)
    }

    func testNegativeCycleCountNormalizesToNil() {
        XCTAssertNil(make(chargePercent: 50, cycleCount: -1).cycleCount)
    }

    func testConditionLocalizedNameDiffersByLanguage() {
        XCTAssertNotEqual(
            BatteryCondition.serviceRecommended.localizedName(in: .english),
            BatteryCondition.serviceRecommended.localizedName(in: .portuguese)
        )
    }

    func testEqualSamplesAreEqual() {
        let timestamp = Date()
        let a = BatterySample(timestamp: timestamp, chargePercent: 80, powerSource: .ac, isCharging: true, timeRemaining: 600, healthCondition: .normal, cycleCount: 42)
        let b = BatterySample(timestamp: timestamp, chargePercent: 80, powerSource: .ac, isCharging: true, timeRemaining: 600, healthCondition: .normal, cycleCount: 42)
        XCTAssertEqual(a, b)
    }
}
