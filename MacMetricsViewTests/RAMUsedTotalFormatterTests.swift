import XCTest
@testable import MacMetricsView

/// Covers the single menu-bar RAM display: real used memory over physical total.
final class RAMUsedTotalFormatterTests: XCTestCase {

    private func sample(
        usedGB: Double = 0,
        totalGB: Double = 16,
        usedPercent: Double = 0,
        pressurePercent: Double = 0,
        pressureLevel: MemoryPressureLevel? = nil
    ) -> RAMSample {
        RAMSample(
            usedGB: usedGB,
            totalGB: totalGB,
            usedPercent: usedPercent,
            pressurePercent: pressurePercent,
            pressureLevel: pressureLevel
        )
    }

    // MARK: - menuBarUsedTotalString

    func testCompactRatioFormatsWithoutSpaces() {
        XCTAssertEqual(RAMFormatter.menuBarUsedTotalString(used: 11.2, total: 16), "11.2/16 GB")
    }

    func testCompactRatioIsTighterThanPopoverHeadline() {
        // The popover uses the spaced form; the menu bar must not.
        XCTAssertEqual(RAMFormatter.usedTotalString(used: 11.2, total: 16), "11.2 / 16 GB")
        XCTAssertEqual(RAMFormatter.menuBarUsedTotalString(used: 11.2, total: 16), "11.2/16 GB")
    }

    func testCompactRatioTotalRendersWhole() {
        XCTAssertEqual(RAMFormatter.menuBarUsedTotalString(used: 8.0, total: 16.0), "8.0/16 GB")
    }

    func testCompactRatioClampsUsedAt999() {
        XCTAssertEqual(RAMFormatter.menuBarUsedTotalString(used: 1500, total: 16), "999.9/16 GB")
    }

    func testCompactRatioPlaceholderOnInvalidInputs() {
        XCTAssertEqual(RAMFormatter.menuBarUsedTotalString(used: nil, total: 16), "--/-- GB")
        XCTAssertEqual(RAMFormatter.menuBarUsedTotalString(used: .nan, total: 16), "--/-- GB")
        XCTAssertEqual(RAMFormatter.menuBarUsedTotalString(used: -1, total: 16), "--/-- GB")
        XCTAssertEqual(RAMFormatter.menuBarUsedTotalString(used: 5, total: 0), "--/-- GB")
        XCTAssertEqual(RAMFormatter.menuBarUsedTotalString(used: 5, total: nil), "--/-- GB")
    }

    // MARK: - valueString routing

    func testValueStringUsedTotalReturnsCompactRatio() {
        let s = sample(usedGB: 11.2, totalGB: 16)
        XCTAssertEqual(RAMFormatter.valueString(for: s), "11.2/16 GB")
    }

    func testMenuBarTitleUsesOnlyUsedTotal() {
        let s = sample(usedGB: 11.2, totalGB: 16, usedPercent: 70, pressurePercent: 99)

        XCTAssertEqual(RAMFormatter.menuBarTitle(for: s), "RAM 11.2/16 GB")
        XCTAssertEqual(RAMFormatter.menuBarTitle(for: s, showLabel: false), "11.2/16 GB")
        XCTAssertFalse(RAMFormatter.menuBarTitle(for: s).contains("%"))
    }

    // MARK: - menuBarTextStyle (color = pressure)

    func testUsedTotalColorFollowsKernelPressureLevel() {
        XCTAssertEqual(
            RAMFormatter.menuBarTextStyle(for: sample(pressureLevel: .warning)),
            .elevatedCPU
        )
        XCTAssertEqual(
            RAMFormatter.menuBarTextStyle(for: sample(pressureLevel: .critical)),
            .highCPU
        )
    }

    func testUsedTotalColorIgnoresMemoryUsedWhenLevelUnavailable() {
        // High Memory Used but low pressure: must stay normal (color is pressure, not fullness).
        let s = sample(usedPercent: 94, pressurePercent: 20, pressureLevel: nil)
        XCTAssertEqual(RAMFormatter.menuBarTextStyle(for: s), .normal)
    }

    func testUsedTotalColorUsesPressurePercentFallback() {
        let s = sample(usedPercent: 30, pressurePercent: 85, pressureLevel: nil)
        XCTAssertEqual(RAMFormatter.menuBarTextStyle(for: s), .highCPU)
    }
}
