import XCTest
@testable import MacMetricsView

/// Direct tests for `AmbientThemeModel` extracted from `CPUState` (task-003). Exercises
/// the model standalone (no `CPUState`) and proves the churn-isolation contract: mutating
/// it must not invalidate `CPUState`'s own `objectWillChange` — `PopoverView` observes
/// `ambient` directly instead (see the comment on `CPUState.ambient`).
@MainActor
final class AmbientThemeModelTests: XCTestCase {
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

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "AmbientThemeModelTests.\(UUID().uuidString)")!
    }

    private func makeModel(
        enabled: Bool = true,
        lowLux: Double = 175,
        highLux: Double = 240,
        dwellSeconds: TimeInterval = 0,
        appearance: FakeSystemAppearance? = nil
    ) -> AmbientThemeModel {
        let defaults = makeDefaults()
        AmbientThemeSettings(
            isEnabled: enabled, lowLux: lowLux, highLux: highLux, dwellSeconds: dwellSeconds
        ).save(to: defaults)
        return AmbientThemeModel(userDefaults: defaults, systemAppearance: appearance ?? FakeSystemAppearance())
    }

    func testUpdateStoresSample() {
        let model = makeModel()
        model.update(with: AmbientLightSample(lux: 200))
        XCTAssertEqual(model.latestSample?.lux, 200)
    }

    func testDarkRoomSuggestsDarkWhenEnabled() {
        let model = makeModel(appearance: FakeSystemAppearance(current: .light))
        model.update(with: AmbientLightSample(lux: 130))
        XCTAssertEqual(model.suggestion, .suggest(.dark))
    }

    func testDisabledNeverSuggests() {
        let model = makeModel(enabled: false)
        model.update(with: AmbientLightSample(lux: 130))
        XCTAssertEqual(model.suggestion, .none)
    }

    func testApplyClearsSuggestionOnSuccess() {
        let appearance = FakeSystemAppearance(current: .light, applyResult: .applied)
        let model = makeModel(appearance: appearance)
        model.update(with: AmbientLightSample(lux: 130))
        XCTAssertEqual(model.suggestion, .suggest(.dark))

        model.apply()

        XCTAssertEqual(appearance.appliedModes, [.dark])
        XCTAssertEqual(model.suggestion, .none)
        XCTAssertEqual(model.lastApplyResult, .applied)
    }

    func testApplyDeniedKeepsSuggestionAndPublishesResult() {
        let appearance = FakeSystemAppearance(current: .light, applyResult: .notAuthorized)
        let model = makeModel(appearance: appearance)
        model.update(with: AmbientLightSample(lux: 130))

        model.apply()

        XCTAssertEqual(model.suggestion, .suggest(.dark), "a denied apply must not clear the banner")
        XCTAssertEqual(model.lastApplyResult, .notAuthorized)
    }

    func testDismissSnoozesDirectionUntilDeadBandReentry() {
        let model = makeModel(appearance: FakeSystemAppearance(current: .light))
        model.update(with: AmbientLightSample(lux: 130))
        XCTAssertEqual(model.suggestion, .suggest(.dark))

        model.dismiss()
        XCTAssertEqual(model.suggestion, .none)

        model.update(with: AmbientLightSample(lux: 130))
        XCTAssertEqual(model.suggestion, .none, "still snoozed for dark while lux stays past the threshold")

        model.update(with: AmbientLightSample(lux: 200))   // back through the dead band
        model.update(with: AmbientLightSample(lux: 130))
        XCTAssertEqual(model.suggestion, .suggest(.dark), "dead-band reentry clears the snooze")
    }

    func testSetSettingsPersistsAndReturnsWhetherChanged() {
        let defaults = makeDefaults()
        let model = AmbientThemeModel(userDefaults: defaults, systemAppearance: FakeSystemAppearance())
        let newSettings = AmbientThemeSettings(isEnabled: true, lowLux: 100, highLux: 200, dwellSeconds: 5)

        XCTAssertTrue(model.setSettings(newSettings))
        XCTAssertEqual(model.settings, newSettings)
        XCTAssertEqual(AmbientThemeSettings.load(from: defaults), newSettings)

        XCTAssertFalse(model.setSettings(newSettings), "no-op when settings are unchanged")
    }

    func testTokenStyleChurnIsolation_AmbientMutationDoesNotEmitCPUStateObjectWillChange() {
        let state = CPUState(userDefaults: makeDefaults(), systemAppearance: FakeSystemAppearance())
        state.setAmbientThemeSettings(
            AmbientThemeSettings(isEnabled: true, lowLux: 175, highLux: 240, dwellSeconds: 0)
        )
        var fired = false
        let cancellable = state.objectWillChange.sink { fired = true }

        state.ambient.update(with: AmbientLightSample(lux: 130))

        XCTAssertFalse(
            fired,
            "ambient mutation must invalidate only AmbientThemeModel; PopoverView observes it directly"
        )
        cancellable.cancel()
    }
}
