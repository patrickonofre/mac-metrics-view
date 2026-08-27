import XCTest
@testable import MacMetricsView

final class CPUFormattingAndHistoryTests: XCTestCase {
    func testFormatterShowsUnavailableForMissingSample() {
        XCTAssertEqual(CPUFormatter.menuBarTitle(for: nil), "CPU  --%")
        XCTAssertEqual(CPUFormatter.menuBarTitle(for: nil, showLabel: false), " --%")
        XCTAssertEqual(CPUFormatter.percentageString(nil), "--%")
        XCTAssertEqual(CPUFormatter.fixedWidthPercentageString(nil), " --%")
        XCTAssertEqual(CPUFormatter.percentageString(.nan), "--%")
        XCTAssertEqual(RAMFormatter.menuBarTitle(for: nil), "RAM --/-- GB")
        XCTAssertEqual(RAMFormatter.menuBarTitle(for: nil, showLabel: false), "--/-- GB")
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

    func testRAMFormatterReturnsUsedTotalWithOneDecimalPlace() {
        let sample = RAMSample(usedGB: 14, totalGB: 16, usedPercent: 87, appMemoryGB: 12.44, appMemoryPercent: 77.75)
        XCTAssertEqual(RAMFormatter.menuBarTitle(for: sample), "RAM 14.0/16 GB")
        XCTAssertEqual(RAMFormatter.menuBarTitle(for: sample, showLabel: false), "14.0/16 GB")
        XCTAssertEqual(RAMFormatter.usedGBString(12.46), "12.5 GB")
        XCTAssertFalse(RAMFormatter.menuBarTitle(for: sample).contains("%"))
    }

    func testRAMFormatterShowsPlaceholderForMissingSample() {
        XCTAssertEqual(RAMFormatter.menuBarTitle(for: nil), "RAM --/-- GB")
        XCTAssertEqual(RAMFormatter.menuBarTextStyle(for: nil), .normal)
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

    func testRAMSeverityUsesPressurePercentFallbackThresholds() {
        func style(_ pct: Double) -> CPUMenuBarTextStyle {
            RAMFormatter.menuBarTextStyle(
                for: RAMSample(usedGB: 10, totalGB: 16, usedPercent: 95, pressurePercent: pct)
            )
        }
        XCTAssertEqual(style(59.9), .normal)
        XCTAssertEqual(style(60), .elevatedCPU)
        XCTAssertEqual(style(79.9), .elevatedCPU)
        XCTAssertEqual(style(80), .highCPU)
    }

    func testRAMSeverityPrefersKernelPressureLevelOverPercent() {
        // Even with used memory at 95%, a NORMAL kernel level wins.
        func style(_ level: MemoryPressureLevel) -> CPUMenuBarTextStyle {
            RAMFormatter.menuBarTextStyle(
                for: RAMSample(usedGB: 15.2, totalGB: 16, usedPercent: 95, pressureLevel: level)
            )
        }
        XCTAssertEqual(style(.normal), .normal)
        XCTAssertEqual(style(.warning), .elevatedCPU)
        XCTAssertEqual(style(.critical), .highCPU)
    }

    func testRAMUsedTotalString() {
        let sample = RAMSample(usedGB: 11.24, totalGB: 16, usedPercent: 70)
        XCTAssertEqual(RAMFormatter.usedTotalString(used: sample.usedGB, total: sample.totalGB), "11.2 / 16 GB")
        XCTAssertEqual(RAMFormatter.usedTotalString(used: nil, total: 16), "-- GB")
        XCTAssertEqual(RAMFormatter.usedTotalString(used: 8, total: 0), "-- GB")
    }

    func testRAMDetailRowsExposeBreakdown() {
        let sample = RAMSample(
            usedGB: 11, totalGB: 16, usedPercent: 70,
            appMemoryGB: 5.2, wiredGB: 2.8, compressedGB: 1.4,
            cachedFilesGB: 3.1, swapUsedGB: 0.5, pressureLevel: .warning
        )
        let rows = RAMFormatter.detailRows(for: sample, .english)
        XCTAssertEqual(rows.map(\.label), ["App Memory", "Wired", "Compressed", "Cached Files", "Swap Used", "Pressure"])
        XCTAssertEqual(rows.map(\.value), ["5.2 GB", "2.8 GB", "1.4 GB", "3.1 GB", "0.5 GB", "Warning"])
        XCTAssertTrue(RAMFormatter.detailRows(for: nil).isEmpty)
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
