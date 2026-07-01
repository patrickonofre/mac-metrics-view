import XCTest
@testable import MacMetricsView

final class GPUFormatterTests: XCTestCase {
    // MARK: - Value formatting

    func testPercentageStringFallsBackWhenNoSample() {
        XCTAssertEqual(GPUFormatter.percentageString(for: nil), "--%")
    }

    func testPercentageStringRoundsSampleValue() {
        XCTAssertEqual(GPUFormatter.percentageString(for: GPUSample(utilizationPercent: 39)), "39%")
    }

    func testPercentageStringClampsAboveHundred() {
        XCTAssertEqual(GPUFormatter.percentageString(for: GPUSample(utilizationPercent: 150)), "100%")
    }

    func testMenuBarTitleWithLabel() {
        XCTAssertEqual(GPUFormatter.menuBarTitle(for: GPUSample(utilizationPercent: 39)), "GPU  39%")
    }

    func testMenuBarTitleWithoutLabelIsFixedWidth() {
        XCTAssertEqual(GPUFormatter.menuBarTitle(for: GPUSample(utilizationPercent: 39), showLabel: false), " 39%")
    }

    func testMenuBarTitleFallsBackWhenNoSample() {
        XCTAssertEqual(GPUFormatter.menuBarTitle(for: nil, showLabel: false), " --%")
    }

    // MARK: - Severity (reuses CPU thresholds)

    func testSeverityNormalBelowEighty() {
        XCTAssertEqual(GPUFormatter.menuBarTextStyle(for: GPUSample(utilizationPercent: 79)), .normal)
    }

    func testSeverityElevatedAtEighty() {
        XCTAssertEqual(GPUFormatter.menuBarTextStyle(for: GPUSample(utilizationPercent: 80)), .elevatedCPU)
    }

    func testSeverityElevatedJustBelowNinety() {
        XCTAssertEqual(GPUFormatter.menuBarTextStyle(for: GPUSample(utilizationPercent: 89)), .elevatedCPU)
    }

    func testSeverityHighAtNinety() {
        XCTAssertEqual(GPUFormatter.menuBarTextStyle(for: GPUSample(utilizationPercent: 90)), .highCPU)
    }

    func testSeverityNormalWhenNoSample() {
        XCTAssertEqual(GPUFormatter.menuBarTextStyle(for: nil), .normal)
    }
}
