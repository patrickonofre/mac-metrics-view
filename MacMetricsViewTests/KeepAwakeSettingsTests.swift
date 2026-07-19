import XCTest
@testable import MacMetricsView

/// Direct tests for `KeepAwakeSettings` (feature `keep-awake-persistence`).
final class KeepAwakeSettingsTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "KeepAwakeSettingsTests.\(UUID().uuidString)")!
    }

    // Edge case: no stored value yet defaults to off (KAWK-03 default preserved).
    func testLoadWithNoStoredValueDefaultsToInactive() {
        let defaults = freshDefaults()

        XCTAssertFalse(KeepAwakeSettings.load(from: defaults).isActive)
    }

    // KAWK-05: turning on persists isActive = true.
    func testSaveTruePersistsActiveState() {
        let defaults = freshDefaults()

        KeepAwakeSettings(isActive: true).save(to: defaults)

        XCTAssertTrue(KeepAwakeSettings.load(from: defaults).isActive)
    }

    // KAWK-05: turning off persists isActive = false.
    func testSaveFalsePersistsInactiveState() {
        let defaults = freshDefaults()
        KeepAwakeSettings(isActive: true).save(to: defaults)

        KeepAwakeSettings(isActive: false).save(to: defaults)

        XCTAssertFalse(KeepAwakeSettings.load(from: defaults).isActive)
    }
}
