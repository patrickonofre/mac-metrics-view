import XCTest
@testable import MacMetricsView

final class LocalizationAmbientKeysTests: XCTestCase {
    func testAllAmbientKeysReturnNonEmptyStringsInBothLanguages() {
        let texts: [LocalizedText] = [
            Strings.ambientSuggestionTitleDark,
            Strings.ambientSuggestionTitleLight,
            Strings.ambientSuggestionMessage,
            Strings.ambientApply,
            Strings.ambientDismiss,
            Strings.ambientNotAuthorizedTitle,
            Strings.ambientNotAuthorizedMessage,
            Strings.ambientOpenAutomationSettings,
            Strings.ambientThemeSectionTitle,
            Strings.ambientThemeEnable,
            Strings.ambientThemeHelp,
            Strings.ambientThresholdDark,
            Strings.ambientThresholdLight,
            Strings.ambientDwellLabel,
            Strings.ambientCurrentLight,
            Strings.ambientNoSensor
        ]

        for text in texts {
            XCTAssertFalse(text(.english).isEmpty)
            XCTAssertFalse(text(.portuguese).isEmpty)
        }
    }

    func testTranslatedKeysDifferByLanguage() {
        XCTAssertNotEqual(Strings.ambientThemeEnable(.english), Strings.ambientThemeEnable(.portuguese))
        XCTAssertNotEqual(Strings.ambientNoSensor(.english), Strings.ambientNoSensor(.portuguese))
    }
}
