import XCTest
@testable import MacMetricsView

final class LocalizationDiskKeysTests: XCTestCase {
    func testAllDiskAccessorsReturnNonEmptyStringsInBothLanguages() {
        let texts: [LocalizedText] = [
            Strings.disk,
            Strings.diskRead,
            Strings.diskWrite,
            Strings.diskRecentTotalRead,
            Strings.diskRecentTotalWrite,
            Strings.diskRecentPeakRead,
            Strings.diskRecentPeakWrite,
            Strings.diskMenuBarMetric,
            Strings.diskMetricCombinedShort,
            Strings.diskMetricSplitShort
        ]

        for text in texts {
            XCTAssertFalse(text(.english).isEmpty)
            XCTAssertFalse(text(.portuguese).isEmpty)
        }
    }

    func testRecentTotalLabelsCommunicateRollingWindow() {
        XCTAssertTrue(Strings.diskRecentTotalRead(.english).contains("45"))
        XCTAssertTrue(Strings.diskRecentTotalWrite(.english).contains("45"))
        XCTAssertTrue(Strings.diskRecentPeakRead(.english).contains("45"))
        XCTAssertTrue(Strings.diskRecentPeakWrite(.english).contains("45"))
    }

    func testCombinedAndSplitShortLabelsAreDistinct() {
        XCTAssertNotEqual(
            Strings.diskMetricCombinedShort(.english),
            Strings.diskMetricSplitShort(.english)
        )
        XCTAssertNotEqual(
            Strings.diskMetricCombinedShort(.portuguese),
            Strings.diskMetricSplitShort(.portuguese)
        )
    }
}
