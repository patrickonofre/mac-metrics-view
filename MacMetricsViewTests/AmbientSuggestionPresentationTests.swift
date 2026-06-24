import XCTest
@testable import MacMetricsView

final class AmbientSuggestionPresentationTests: XCTestCase {
    func testHiddenWhenNoneAndNoApply() {
        XCTAssertEqual(
            AmbientSuggestionPresentation.bannerState(suggestion: .none, lastApply: nil),
            .hidden
        )
    }

    func testSuggestionMapsToBanner() {
        XCTAssertEqual(
            AmbientSuggestionPresentation.bannerState(suggestion: .suggest(.dark), lastApply: nil),
            .suggestion(.dark)
        )
        XCTAssertEqual(
            AmbientSuggestionPresentation.bannerState(suggestion: .suggest(.light), lastApply: .applied),
            .suggestion(.light)
        )
    }

    func testNotAuthorizedTakesPriorityOverSuggestion() {
        XCTAssertEqual(
            AmbientSuggestionPresentation.bannerState(suggestion: .suggest(.dark), lastApply: .notAuthorized),
            .notAuthorized
        )
    }

    func testAppliedResultDoesNotShowBannerWhenNoSuggestion() {
        XCTAssertEqual(
            AmbientSuggestionPresentation.bannerState(suggestion: .none, lastApply: .applied),
            .hidden
        )
    }

    func testTitlesDifferByModeAndLanguage() {
        XCTAssertEqual(AmbientSuggestionPresentation.title(for: .dark, .english), "Switch to Dark theme?")
        XCTAssertEqual(AmbientSuggestionPresentation.title(for: .light, .portuguese), "Mudar para o tema Claro?")
        XCTAssertNotEqual(
            AmbientSuggestionPresentation.title(for: .dark, .english),
            AmbientSuggestionPresentation.title(for: .light, .english)
        )
    }

    func testAutomationSettingsURLResolves() {
        XCTAssertNotNil(AmbientSuggestionPresentation.automationSettingsURL())
    }
}
