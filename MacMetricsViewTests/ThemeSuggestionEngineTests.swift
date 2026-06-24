import XCTest
@testable import MacMetricsView

final class ThemeSuggestionEngineTests: XCTestCase {
    // Band: dark below 175, light above 240, dead band 175...240, dwell 20s.
    private func makeEngine(dwell: TimeInterval = 20) -> ThemeSuggestionEngine {
        ThemeSuggestionEngine(settings: AmbientThemeSettings(
            isEnabled: true, lowLux: 175, highLux: 240, dwellSeconds: dwell
        ))
    }

    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func t(_ offset: TimeInterval) -> Date { t0.addingTimeInterval(offset) }

    func testDarkRoomAfterDwellSuggestsDark() {
        let engine = makeEngine()
        XCTAssertEqual(engine.evaluate(lux: 130, current: .light, now: t(0)), .none)   // starts dwell
        XCTAssertEqual(engine.evaluate(lux: 130, current: .light, now: t(20)), .suggest(.dark))
    }

    func testBrightRoomAfterDwellSuggestsLight() {
        let engine = makeEngine()
        XCTAssertEqual(engine.evaluate(lux: 260, current: .dark, now: t(0)), .none)
        XCTAssertEqual(engine.evaluate(lux: 260, current: .dark, now: t(20)), .suggest(.light))
    }

    func testDwellNotElapsedYieldsNone() {
        let engine = makeEngine()
        XCTAssertEqual(engine.evaluate(lux: 130, current: .light, now: t(0)), .none)
        XCTAssertEqual(engine.evaluate(lux: 130, current: .light, now: t(10)), .none)
    }

    func testCandidateEqualToCurrentNeverSuggests() {
        let engine = makeEngine()
        // Dark outside but system already dark → nothing to suggest (FR-6).
        XCTAssertEqual(engine.evaluate(lux: 130, current: .dark, now: t(0)), .none)
        XCTAssertEqual(engine.evaluate(lux: 130, current: .dark, now: t(60)), .none)
    }

    func testDeadBandYieldsNone() {
        let engine = makeEngine()
        XCTAssertEqual(engine.evaluate(lux: 200, current: .light, now: t(0)), .none)
        XCTAssertEqual(engine.evaluate(lux: 200, current: .dark, now: t(60)), .none)
    }

    func testThresholdBoundariesAreDeadBand() {
        let engine = makeEngine()
        // lux == lowLux is not < lowLux; lux == highLux is not > highLux.
        XCTAssertEqual(engine.evaluate(lux: 175, current: .light, now: t(0)), .none)
        XCTAssertEqual(engine.evaluate(lux: 240, current: .dark, now: t(60)), .none)
    }

    func testTransientExcursionBelowDwellDoesNotMature() {
        let engine = makeEngine()
        XCTAssertEqual(engine.evaluate(lux: 130, current: .light, now: t(0)), .none)   // dwell starts
        XCTAssertEqual(engine.evaluate(lux: 200, current: .light, now: t(5)), .none)   // dead band resets dwell
        XCTAssertEqual(engine.evaluate(lux: 130, current: .light, now: t(10)), .none)  // restart, not carry-over
        // 15s after the restart (t=25) is still < 20s of continuous dwell → no suggestion.
        XCTAssertEqual(engine.evaluate(lux: 130, current: .light, now: t(25)), .none)
        // 20s after the restart matures it.
        XCTAssertEqual(engine.evaluate(lux: 130, current: .light, now: t(30)), .suggest(.dark))
    }

    func testDismissSnoozesSameDirectionUntilDeadBand() {
        let engine = makeEngine()
        XCTAssertEqual(engine.evaluate(lux: 130, current: .light, now: t(0)), .none)
        XCTAssertEqual(engine.evaluate(lux: 130, current: .light, now: t(20)), .suggest(.dark))

        engine.dismiss(.suggest(.dark))
        // Still dark, still past dwell, but snoozed → silent.
        XCTAssertEqual(engine.evaluate(lux: 130, current: .light, now: t(40)), .none)

        // Returning through the dead band clears the snooze.
        XCTAssertEqual(engine.evaluate(lux: 200, current: .light, now: t(45)), .none)

        // Dark again → fresh dwell → suggests once more.
        XCTAssertEqual(engine.evaluate(lux: 130, current: .light, now: t(50)), .none)
        XCTAssertEqual(engine.evaluate(lux: 130, current: .light, now: t(70)), .suggest(.dark))
    }

    func testDismissNoneIsNoOp() {
        let engine = makeEngine()
        engine.dismiss(.none)
        XCTAssertEqual(engine.evaluate(lux: 130, current: .light, now: t(0)), .none)
        XCTAssertEqual(engine.evaluate(lux: 130, current: .light, now: t(20)), .suggest(.dark))
    }

    func testZeroDwellSuggestsImmediately() {
        let engine = makeEngine(dwell: 0)
        XCTAssertEqual(engine.evaluate(lux: 130, current: .light, now: t(0)), .suggest(.dark))
    }
}
