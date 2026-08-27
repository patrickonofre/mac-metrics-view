import XCTest
@testable import MacMetricsView

/// Coverage for RAM detail localization keys, mirroring the disk/battery key tests.
final class LocalizationRAMKeysTests: XCTestCase {
    func testRAMDetailAccessorsReturnNonEmptyStringsInBothLanguages() {
        let texts: [LocalizedText] = [
            Strings.ramAppMemory,
            Strings.ramPressure,
            Strings.ramWired,
            Strings.ramCompressed,
            Strings.ramCachedFiles,
            Strings.ramSwapUsed
        ]

        for text in texts {
            XCTAssertFalse(text(.english).isEmpty)
            XCTAssertFalse(text(.portuguese).isEmpty)
        }
    }

    func testRAMDetailLabelsAreDistinct() {
        let labels = [
            Strings.ramAppMemory(.english),
            Strings.ramPressure(.english),
            Strings.ramWired(.english),
            Strings.ramCompressed(.english),
            Strings.ramCachedFiles(.english),
            Strings.ramSwapUsed(.english)
        ]

        XCTAssertEqual(Set(labels).count, labels.count)
    }
}
