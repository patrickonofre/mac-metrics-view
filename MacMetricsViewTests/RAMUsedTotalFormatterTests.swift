import XCTest
@testable import MacMetricsView

/// Covers the menu-bar "Used / Total" RAM mode: the compact ratio formatter, the
/// `valueString` routing, and the pressure-driven color in `usedTotal` mode
/// (ADR-002 / ADR-003).
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
        XCTAssertEqual(RAMFormatter.valueString(for: s, metric: .usedTotal), "11.2/16 GB")
    }

    // MARK: - menuBarTextStyle (color = pressure, ADR-003)

    func testUsedTotalColorFollowsKernelPressureLevel() {
        XCTAssertEqual(
            RAMFormatter.menuBarTextStyle(for: sample(pressureLevel: .warning), metric: .usedTotal),
            .elevatedCPU
        )
        XCTAssertEqual(
            RAMFormatter.menuBarTextStyle(for: sample(pressureLevel: .critical), metric: .usedTotal),
            .highCPU
        )
    }

    func testUsedTotalColorIgnoresMemoryUsedWhenLevelUnavailable() {
        // High Memory Used but low pressure: must stay normal (color is pressure, not fullness).
        let s = sample(usedPercent: 94, pressurePercent: 20, pressureLevel: nil)
        XCTAssertEqual(RAMFormatter.menuBarTextStyle(for: s, metric: .usedTotal), .normal)
    }

    func testUsedTotalColorUsesPressurePercentFallback() {
        let s = sample(usedPercent: 30, pressurePercent: 85, pressureLevel: nil)
        XCTAssertEqual(RAMFormatter.menuBarTextStyle(for: s, metric: .usedTotal), .highCPU)
    }
}
