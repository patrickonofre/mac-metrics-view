import XCTest
@testable import MacMetricsView

final class BatteryFormatterTests: XCTestCase {
    private func sample(
        charge: Int?,
        charging: Bool = false,
        source: BatteryPowerSource = .battery,
        time: TimeInterval? = 3600,
        condition: BatteryCondition = .normal,
        cycles: Int? = 100
    ) -> BatterySample {
        BatterySample(
            chargePercent: charge,
            powerSource: source,
            isCharging: charging,
            timeRemaining: time,
            healthCondition: condition,
            cycleCount: cycles
        )
    }

    func testGlyphBucketsByCharge() {
        XCTAssertEqual(BatteryFormatter.menuBarGlyphName(for: sample(charge: 5)), "battery.0")
        XCTAssertEqual(BatteryFormatter.menuBarGlyphName(for: sample(charge: 30)), "battery.25")
        XCTAssertEqual(BatteryFormatter.menuBarGlyphName(for: sample(charge: 55)), "battery.50")
        XCTAssertEqual(BatteryFormatter.menuBarGlyphName(for: sample(charge: 80)), "battery.75")
        XCTAssertEqual(BatteryFormatter.menuBarGlyphName(for: sample(charge: 100)), "battery.100")
    }

    func testGlyphUsesBoltVariantWhileCharging() {
        XCTAssertEqual(BatteryFormatter.menuBarGlyphName(for: sample(charge: 5, charging: true)), "battery.0.bolt")
        XCTAssertEqual(BatteryFormatter.menuBarGlyphName(for: sample(charge: 100, charging: true)), "battery.100.bolt")
    }

    func testGlyphFallsBackToEmptyWhenChargeUnknown() {
        XCTAssertEqual(BatteryFormatter.menuBarGlyphName(for: nil), "battery.0")
    }

    func testValueFormatting() {
        XCTAssertEqual(BatteryFormatter.menuBarValue(for: sample(charge: 82)), "82%")
        XCTAssertEqual(BatteryFormatter.menuBarValue(for: nil), "--")
    }

    func testLowChargeSeverity() {
        XCTAssertEqual(BatteryFormatter.menuBarTextStyle(for: sample(charge: 8)), .highCPU)
        XCTAssertEqual(BatteryFormatter.menuBarTextStyle(for: sample(charge: 18)), .elevatedCPU)
        XCTAssertEqual(BatteryFormatter.menuBarTextStyle(for: sample(charge: 60)), .normal)
    }

    func testSeveritySuppressedWhileCharging() {
        XCTAssertEqual(BatteryFormatter.menuBarTextStyle(for: sample(charge: 8, charging: true)), .normal)
    }

    func testTimeRemainingFormatting() {
        // 2h 05m
        XCTAssertEqual(BatteryFormatter.timeRemainingString(sample(charge: 50, time: 7500)), "2h 05m")
    }

    func testTimeRemainingCalculatingWhenNil() {
        let s = sample(charge: 50, time: -1)   // sentinel → nil
        XCTAssertEqual(BatteryFormatter.timeRemainingString(s), Strings.batteryCalculating())
    }

    func testDetailRowsEmptyWhenNoSample() {
        XCTAssertTrue(BatteryFormatter.detailRows(for: nil).isEmpty)
    }

    func testDetailRowsIncludeServiceConditionAndCycles() {
        let rows = BatteryFormatter.detailRows(for: sample(charge: 50, condition: .serviceRecommended, cycles: 321), .english)
        let values = rows.map(\.value)
        XCTAssertTrue(values.contains(BatteryCondition.serviceRecommended.localizedName(in: .english)))
        XCTAssertTrue(values.contains("321"))
    }
}
