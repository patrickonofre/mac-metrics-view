import XCTest
@testable import MacMetricsView

/// Covers the single RAM menu-bar mode replacing the old picker.
final class RAMSingleDisplayModeTests: XCTestCase {

    func testMenuBarRAMDisplayHasNoAlternateMode() {
        let sample = RAMSample(
            usedGB: 6.34,
            totalGB: 8,
            usedPercent: 79.25,
            appMemoryGB: 4.2,
            appMemoryPercent: 52.5,
            pressurePercent: 61
        )

        XCTAssertEqual(RAMFormatter.menuBarTitle(for: sample, showLabel: false), "6.3/8 GB")
        XCTAssertFalse(RAMFormatter.menuBarTitle(for: sample, showLabel: false).contains("%"))
    }
}
