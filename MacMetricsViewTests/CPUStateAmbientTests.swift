import XCTest
@testable import MacMetricsView

@MainActor
final class CPUStateAmbientTests: XCTestCase {
    private final class FakeSystemAppearance: SystemAppearanceControlling {
        var current: SystemAppearanceMode
        var applyResult: AppearanceApplyResult
        private(set) var appliedModes: [SystemAppearanceMode] = []

        init(current: SystemAppearanceMode = .light, applyResult: AppearanceApplyResult = .applied) {
            self.current = current
            self.applyResult = applyResult
        }

        func apply(_ mode: SystemAppearanceMode) -> AppearanceApplyResult {
            appliedModes.append(mode)
            return applyResult
        }
    }

    private func makeState(
        settings: AmbientThemeSettings = AmbientThemeSettings(isEnabled: true, lowLux: 175, highLux: 240, dwellSeconds: 0),
        appearance: FakeSystemAppearance? = nil
    ) -> CPUState {
        let resolvedAppearance = appearance ?? FakeSystemAppearance()
        let suiteName = "MacMetricsViewTests.CPUStateAmbient.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        ud.removePersistentDomain(forName: suiteName)
        settings.save(to: ud)   // CPUState loads ambient settings in init
        return CPUState(
            userDefaults: ud,
            accessibilityAuthorization: FakeAccessibilityAuthorization(isTrusted: false),
            systemAppearance: resolvedAppearance
        )
    }

    func testUpdateStoresSample() {
        let state = makeState()
        state.update(with: AmbientLightSample(lux: 200))
        XCTAssertEqual(state.latestAmbientSample?.lux, 200)
    }

    func testDarkRoomSuggestsDarkWhenEnabled() {
        let state = makeState(appearance: FakeSystemAppearance(current: .light))
        state.update(with: AmbientLightSample(lux: 130))
        XCTAssertEqual(state.themeSuggestion, .suggest(.dark))
    }

    func testDisabledNeverSuggests() {
        let state = makeState(settings: AmbientThemeSettings(isEnabled: false, lowLux: 175, highLux: 240, dwellSeconds: 0))
        state.update(with: AmbientLightSample(lux: 130))
        XCTAssertEqual(state.themeSuggestion, .none)
    }

    func testNoSuggestionWhenAlreadyInTargetMode() {
        let state = makeState(appearance: FakeSystemAppearance(current: .dark))
        state.update(with: AmbientLightSample(lux: 130))   // dark room but system already dark
        XCTAssertEqual(state.themeSuggestion, .none)
    }

    func testApplyFlipsAppearanceAndClearsSuggestion() {
        let appearance = FakeSystemAppearance(current: .light)
        let state = makeState(appearance: appearance)
        state.update(with: AmbientLightSample(lux: 130))
        XCTAssertEqual(state.themeSuggestion, .suggest(.dark))

        state.applyThemeSuggestion()

        XCTAssertEqual(appearance.appliedModes, [.dark])
        XCTAssertEqual(state.themeSuggestion, .none)
        XCTAssertEqual(state.lastAppearanceApplyResult, .applied)
    }

    func testApplyNotAuthorizedKeepsSuggestionAndPublishesResult() {
        let appearance = FakeSystemAppearance(current: .light, applyResult: .notAuthorized)
        let state = makeState(appearance: appearance)
        state.update(with: AmbientLightSample(lux: 130))

        state.applyThemeSuggestion()

        XCTAssertEqual(state.themeSuggestion, .suggest(.dark))   // unchanged — couldn't apply
        XCTAssertEqual(state.lastAppearanceApplyResult, .notAuthorized)
    }

    func testDismissClearsAndSnoozesUntilDeadBand() {
        let state = makeState(appearance: FakeSystemAppearance(current: .light))
        state.update(with: AmbientLightSample(lux: 130))
        XCTAssertEqual(state.themeSuggestion, .suggest(.dark))

        state.dismissThemeSuggestion()
        XCTAssertEqual(state.themeSuggestion, .none)

        // Still dark → snoozed, no re-suggestion.
        state.update(with: AmbientLightSample(lux: 130))
        XCTAssertEqual(state.themeSuggestion, .none)

        // Dead band clears snooze; dark again suggests once more.
        state.update(with: AmbientLightSample(lux: 200))
        state.update(with: AmbientLightSample(lux: 130))
        XCTAssertEqual(state.themeSuggestion, .suggest(.dark))
    }

    func testSetSettingsFiresCallbackAndReevaluates() {
        let state = makeState(settings: AmbientThemeSettings(isEnabled: false, lowLux: 175, highLux: 240, dwellSeconds: 0))
        var captured: AmbientThemeSettings?
        state.onAmbientThemeSettingsChange = { captured = $0 }
        state.update(with: AmbientLightSample(lux: 130))
        XCTAssertEqual(state.themeSuggestion, .none)   // disabled

        state.setAmbientThemeSettings(AmbientThemeSettings(isEnabled: true, lowLux: 175, highLux: 240, dwellSeconds: 0))

        XCTAssertEqual(captured?.isEnabled, true)
        XCTAssertEqual(state.themeSuggestion, .suggest(.dark))   // re-evaluated with last sample
    }
}
