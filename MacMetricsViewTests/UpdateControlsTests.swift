import XCTest
@testable import MacMetricsView

@MainActor
final class UpdateControlsTests: XCTestCase {

    private func makeState() -> CPUState {
        let suiteName = "MacMetricsViewTests.UpdateControls.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        ud.removePersistentDomain(forName: suiteName)
        return CPUState(
            userDefaults: ud,
            accessibilityAuthorization: FakeAccessibilityAuthorization(isTrusted: false)
        )
    }

    // MARK: - CPUState.availableUpdateVersion

    func testAvailableUpdateVersionDefaultsToNil() {
        XCTAssertNil(makeState().availableUpdateVersion)
    }

    func testSetAvailableUpdateVersionPublishesValue() {
        let state = makeState()

        state.setAvailableUpdateVersion("1.1.0")

        XCTAssertEqual(state.availableUpdateVersion, "1.1.0")
    }

    func testSetAvailableUpdateVersionNilClearsValue() {
        let state = makeState()
        state.setAvailableUpdateVersion("1.1.0")

        state.setAvailableUpdateVersion(nil)

        XCTAssertNil(state.availableUpdateVersion)
    }

    // MARK: - Localization.autoUpdateAvailable

    func testAutoUpdateAvailablePortuguese() {
        XCTAssertEqual(
            Strings.autoUpdateAvailable("1.1.0", .portuguese),
            "Nova versão 1.1.0 disponível"
        )
    }

    func testAutoUpdateAvailableEnglish() {
        XCTAssertEqual(
            Strings.autoUpdateAvailable("1.1.0", .english),
            "New version 1.1.0 available"
        )
    }

    func testCheckForUpdatesInvokesClosureExactlyOnce() {
        let state = makeState()
        var callCount = 0
        state.onCheckForUpdates = {
            callCount += 1
        }
        state.checkForUpdates()
        XCTAssertEqual(callCount, 1)
    }

    func testSettingAndClearingAvailableUpdateVersionFlipsVisibility() {
        let state = makeState()
        XCTAssertFalse(UpdateBannerPresentation.showsBanner(availableVersion: state.availableUpdateVersion))
        
        state.setAvailableUpdateVersion("1.9.1")
        XCTAssertTrue(UpdateBannerPresentation.showsBanner(availableVersion: state.availableUpdateVersion))
        
        state.setAvailableUpdateVersion(nil)
        XCTAssertFalse(UpdateBannerPresentation.showsBanner(availableVersion: state.availableUpdateVersion))
    }
}
