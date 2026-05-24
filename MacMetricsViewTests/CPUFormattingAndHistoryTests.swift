import XCTest
@testable import MacMetricsView

final class CPUFormattingAndHistoryTests: XCTestCase {
    func testFormatterShowsUnavailableForMissingSample() {
        XCTAssertEqual(CPUFormatter.menuBarTitle(for: nil), "CPU  --%")
        XCTAssertEqual(CPUFormatter.menuBarTitle(for: nil, showLabel: false), " --%")
        XCTAssertEqual(CPUFormatter.percentageString(nil), "--%")
        XCTAssertEqual(CPUFormatter.fixedWidthPercentageString(nil), " --%")
        XCTAssertEqual(CPUFormatter.percentageString(.nan), "--%")
        XCTAssertEqual(RAMFormatter.menuBarTitle(for: nil), "RAM -- GB")
        XCTAssertEqual(RAMFormatter.menuBarTitle(for: nil, showLabel: false), "-- GB")
        XCTAssertEqual(RAMFormatter.usedGBString(nil), "-- GB")
        XCTAssertEqual(RAMFormatter.fixedWidthUsedGBString(nil), "-- GB")
        XCTAssertEqual(RAMFormatter.usedGBString(.nan), "-- GB")
    }

    func testFormatterClampsDisplayValues() {
        XCTAssertEqual(CPUFormatter.percentageString(-12), "0%")
        XCTAssertEqual(CPUFormatter.percentageString(101.2), "100%")
        XCTAssertEqual(CPUFormatter.percentageString(18.4), "18%")
        XCTAssertEqual(CPUFormatter.percentageString(18.5), "19%")
    }

    func testFormatterReturnsFixedWidthPercentagesForMenuBar() {
        XCTAssertEqual(CPUFormatter.fixedWidthPercentageString(6), "  6%")
        XCTAssertEqual(CPUFormatter.fixedWidthPercentageString(18), " 18%")
        XCTAssertEqual(CPUFormatter.fixedWidthPercentageString(100), "100%")
    }

    func testFormatterReturnsNormalStyleBelowElevatedCPUThreshold() {
        let sample = CPUSample(totalUsagePercent: 79.9)

        XCTAssertEqual(CPUFormatter.menuBarTextStyle(for: sample), .normal)
    }

    func testFormatterReturnsElevatedCPUStyleAtThreshold() {
        let sample = CPUSample(totalUsagePercent: 80)

        XCTAssertEqual(CPUFormatter.menuBarTextStyle(for: sample), .elevatedCPU)
    }

    func testFormatterReturnsElevatedCPUStyleAboveElevatedThresholdAndBelowHighThreshold() {
        let sample = CPUSample(totalUsagePercent: 89.9)

        XCTAssertEqual(CPUFormatter.menuBarTextStyle(for: sample), .elevatedCPU)
    }

    func testFormatterReturnsHighCPUStyleAtHighThreshold() {
        let sample = CPUSample(totalUsagePercent: 90)

        XCTAssertEqual(CPUFormatter.menuBarTextStyle(for: sample), .highCPU)
    }

    func testFormatterReturnsHighCPUStyleAboveHighThreshold() {
        let sample = CPUSample(totalUsagePercent: 95)

        XCTAssertEqual(CPUFormatter.menuBarTextStyle(for: sample), .highCPU)
    }

    func testRAMFormatterReturnsGBWithOneDecimalPlace() {
        XCTAssertEqual(RAMFormatter.menuBarTitle(for: RAMSample(usedGB: 12.44, totalGB: 16, usedPercent: 77.75)), "RAM 12.4 GB")
        XCTAssertEqual(RAMFormatter.menuBarTitle(for: RAMSample(usedGB: 12.44, totalGB: 16, usedPercent: 77.75), showLabel: false), "12.4 GB")
        XCTAssertEqual(RAMFormatter.usedGBString(12.46), "12.5 GB")
        XCTAssertFalse(RAMFormatter.menuBarTitle(for: RAMSample(usedGB: 12.4, totalGB: 16, usedPercent: 77.5)).contains("%"))
    }

    func testRAMFormatterReturnsCompactGBForMenuBar() {
        XCTAssertEqual(RAMFormatter.fixedWidthUsedGBString(7.3), "7.3 GB")
        XCTAssertEqual(RAMFormatter.fixedWidthUsedGBString(12.4), "12.4 GB")
        XCTAssertEqual(RAMFormatter.fixedWidthUsedGBString(128.0), "128.0 GB")
    }

    func testRAMFormatterRejectsInvalidValues() {
        XCTAssertEqual(RAMFormatter.usedGBString(-1), "-- GB")
        XCTAssertEqual(RAMFormatter.usedGBString(.infinity), "-- GB")
    }

    func testRAMSeverityReturnsNormalBelowElevatedThreshold() {
        let sample = RAMSample(usedGB: 10, totalGB: 16, usedPercent: 79.9)

        XCTAssertEqual(RAMFormatter.menuBarTextStyle(for: sample), .normal)
    }

    func testRAMSeverityReturnsElevatedAtThreshold() {
        let sample = RAMSample(usedGB: 12.8, totalGB: 16, usedPercent: 80)

        XCTAssertEqual(RAMFormatter.menuBarTextStyle(for: sample), .elevatedCPU)
    }

    func testRAMSeverityReturnsElevatedAboveElevatedThresholdAndBelowHighThreshold() {
        let sample = RAMSample(usedGB: 14.3, totalGB: 16, usedPercent: 89.9)

        XCTAssertEqual(RAMFormatter.menuBarTextStyle(for: sample), .elevatedCPU)
    }

    func testRAMSeverityReturnsHighAtHighThreshold() {
        let sample = RAMSample(usedGB: 14.4, totalGB: 16, usedPercent: 90)

        XCTAssertEqual(RAMFormatter.menuBarTextStyle(for: sample), .highCPU)
    }

    func testRAMSeverityReturnsHighAboveHighThreshold() {
        let sample = RAMSample(usedGB: 15.2, totalGB: 16, usedPercent: 95)

        XCTAssertEqual(RAMFormatter.menuBarTextStyle(for: sample), .highCPU)
    }

    func testCPUHistoryKeepsCapacityAndDropsOldestSamples() {
        var history = CPUHistory(capacity: 3)

        history.append(CPUSample(totalUsagePercent: 1))
        history.append(CPUSample(totalUsagePercent: 2))
        history.append(CPUSample(totalUsagePercent: 3))
        history.append(CPUSample(totalUsagePercent: 4))

        XCTAssertEqual(history.samples.map(\.totalUsagePercent), [2, 3, 4])
    }

    func testRAMHistoryKeepsCapacityAndDropsOldestSamples() {
        var history = RAMHistory(capacity: 3)

        history.append(RAMSample(usedGB: 1, totalGB: 16, usedPercent: 10))
        history.append(RAMSample(usedGB: 2, totalGB: 16, usedPercent: 20))
        history.append(RAMSample(usedGB: 3, totalGB: 16, usedPercent: 30))
        history.append(RAMSample(usedGB: 4, totalGB: 16, usedPercent: 40))

        XCTAssertEqual(history.samples.map(\.usedGB), [2, 3, 4])
    }
}
