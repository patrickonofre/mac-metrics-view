import XCTest
@testable import MacMetricsView

final class AmbientLightModelsTests: XCTestCase {
    func testSampleRetainsLuxAndTimestamp() {
        let now = Date()
        let sample = AmbientLightSample(lux: 261, timestamp: now)

        XCTAssertEqual(sample.lux, 261)
        XCTAssertEqual(sample.timestamp, now)
    }

    func testEqualSamplesAreEqual() {
        let now = Date()
        XCTAssertEqual(
            AmbientLightSample(lux: 130, timestamp: now),
            AmbientLightSample(lux: 130, timestamp: now)
        )
    }

    func testAppearanceModeOppositeFlips() {
        XCTAssertEqual(SystemAppearanceMode.light.opposite, .dark)
        XCTAssertEqual(SystemAppearanceMode.dark.opposite, .light)
    }

    func testThemeSuggestionEquatable() {
        XCTAssertEqual(ThemeSuggestion.none, ThemeSuggestion.none)
        XCTAssertEqual(ThemeSuggestion.suggest(.dark), ThemeSuggestion.suggest(.dark))
        XCTAssertNotEqual(ThemeSuggestion.suggest(.dark), ThemeSuggestion.suggest(.light))
        XCTAssertNotEqual(ThemeSuggestion.none, ThemeSuggestion.suggest(.light))
    }

    func testApplyResultEquatable() {
        XCTAssertEqual(AppearanceApplyResult.applied, .applied)
        XCTAssertNotEqual(AppearanceApplyResult.applied, .notAuthorized)
        XCTAssertNotEqual(AppearanceApplyResult.notAuthorized, .failed)
    }
}
