import XCTest
import IOKit.ps
@testable import MacMetricsView

/// Exercises the pure `IOKitBatteryReader.makeSample(from:cycleCount:)` mapping with
/// synthetic IOPS power-source descriptions. The live IOKit reads (`readSample`,
/// `readCycleCount`, empty-list → nil on desktops) are verified manually in task_11.
final class IOKitBatteryReaderTests: XCTestCase {
    private func description(
        current: Int = 50,
        max: Int = 100,
        state: String = kIOPSBatteryPowerValue,
        charging: Bool = false,
        timeToEmpty: Int? = nil,
        timeToFull: Int? = nil,
        condition: String? = nil
    ) -> [String: Any] {
        var dict: [String: Any] = [
            kIOPSCurrentCapacityKey: current,
            kIOPSMaxCapacityKey: max,
            kIOPSPowerSourceStateKey: state,
            kIOPSIsChargingKey: charging
        ]
        if let timeToEmpty { dict[kIOPSTimeToEmptyKey] = timeToEmpty }
        if let timeToFull { dict[kIOPSTimeToFullChargeKey] = timeToFull }
        if let condition { dict[kIOPSBatteryHealthConditionKey] = condition }
        return dict
    }

    func testChargePercentFromCurrentOverMax() {
        let sample = IOKitBatteryReader.makeSample(from: description(current: 41, max: 82), cycleCount: 10)
        XCTAssertEqual(sample.chargePercent, 50)
    }

    func testTimeToEmptySentinelMapsToNil() {
        let sample = IOKitBatteryReader.makeSample(from: description(timeToEmpty: -1), cycleCount: nil)
        XCTAssertNil(sample.timeRemaining)
    }

    func testTimeToEmptyMinutesConvertToSeconds() {
        let sample = IOKitBatteryReader.makeSample(from: description(timeToEmpty: 120), cycleCount: nil)
        XCTAssertEqual(sample.timeRemaining, 7200)
    }

    func testChargingUsesTimeToFull() {
        let sample = IOKitBatteryReader.makeSample(
            from: description(state: kIOPSACPowerValue, charging: true, timeToFull: 30),
            cycleCount: nil
        )
        XCTAssertTrue(sample.isCharging)
        XCTAssertEqual(sample.timeRemaining, 1800)
    }

    func testACPowerStateMapsToAC() {
        let sample = IOKitBatteryReader.makeSample(from: description(state: kIOPSACPowerValue), cycleCount: nil)
        XCTAssertEqual(sample.powerSource, .ac)
    }

    func testBatteryPowerStateMapsToBattery() {
        let sample = IOKitBatteryReader.makeSample(from: description(state: kIOPSBatteryPowerValue), cycleCount: nil)
        XCTAssertEqual(sample.powerSource, .battery)
    }

    func testServiceRecommendedConditionMapped() {
        let sample = IOKitBatteryReader.makeSample(from: description(condition: "Service Recommended"), cycleCount: nil)
        XCTAssertEqual(sample.healthCondition, .serviceRecommended)
    }

    func testAbsentConditionIsNormal() {
        let sample = IOKitBatteryReader.makeSample(from: description(), cycleCount: nil)
        XCTAssertEqual(sample.healthCondition, .normal)
    }

    func testMissingCycleCountStaysNil() {
        let sample = IOKitBatteryReader.makeSample(from: description(), cycleCount: nil)
        XCTAssertNil(sample.cycleCount)
    }

    func testCycleCountForwarded() {
        let sample = IOKitBatteryReader.makeSample(from: description(), cycleCount: 321)
        XCTAssertEqual(sample.cycleCount, 321)
    }
}
