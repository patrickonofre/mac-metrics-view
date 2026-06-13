import XCTest
@testable import MacMetricsView

final class LocalizationBatteryKeysTests: XCTestCase {
    func testAllBatteryAccessorsReturnNonEmptyStringsInBothLanguages() {
        let texts: [LocalizedText] = [
            Strings.battery,
            Strings.batteryPowerSource,
            Strings.batteryOnAC,
            Strings.batteryOnBattery,
            Strings.batteryTimeRemaining,
            Strings.batteryCalculating,
            Strings.batteryHealth,
            Strings.batteryHealthNormal,
            Strings.batteryServiceRecommended,
            Strings.batteryCycles,
            Strings.batteryNoBattery
        ]

        for text in texts {
            XCTAssertFalse(text(.english).isEmpty)
            XCTAssertFalse(text(.portuguese).isEmpty)
        }
    }

    func testHealthConditionLabelsDifferByLanguage() {
        XCTAssertNotEqual(
            Strings.batteryServiceRecommended(.english),
            Strings.batteryServiceRecommended(.portuguese)
        )
    }

    func testNoBatteryLabelDiffersByLanguage() {
        XCTAssertNotEqual(
            Strings.batteryNoBattery(.english),
            Strings.batteryNoBattery(.portuguese)
        )
    }
}
