import XCTest
@testable import MacMetricsView

/// Coverage for the Used/Total RAM localization keys (task_02), mirroring the
/// disk/battery key tests.
final class LocalizationRAMKeysTests: XCTestCase {
    func testUsedTotalAccessorsReturnNonEmptyStringsInBothLanguages() {
        let texts: [LocalizedText] = [
            Strings.ramMetricUsedTotalShort,
            Strings.ramUsedTotal,
            Strings.ramUsedTotalHelp
        ]

        for text in texts {
            XCTAssertFalse(text(.english).isEmpty)
            XCTAssertFalse(text(.portuguese).isEmpty)
        }
    }

    func testUsedTotalHelpIsDistinctFromOtherModeHelp() {
        XCTAssertNotEqual(Strings.ramUsedTotalHelp(.english), Strings.ramAppMemoryHelp(.english))
        XCTAssertNotEqual(Strings.ramUsedTotalHelp(.english), Strings.ramPressureHelp(.english))
        XCTAssertNotEqual(Strings.ramUsedTotalHelp(.portuguese), Strings.ramAppMemoryHelp(.portuguese))
    }

    func testUsedTotalShortLabelDistinctFromOtherModeLabels() {
        XCTAssertNotEqual(
            Strings.ramMetricUsedTotalShort(.english),
            Strings.ramMetricAppMemoryShort(.english)
        )
        XCTAssertNotEqual(
            Strings.ramMetricUsedTotalShort(.english),
            Strings.ramMetricPressureShort(.english)
        )
    }
}
