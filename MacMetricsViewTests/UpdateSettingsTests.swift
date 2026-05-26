import XCTest
@testable import MacMetricsView

final class UpdateSettingsTests: XCTestCase {
    func testDefaultsToEnabledWhenValueIsMissing() {
        let userDefaults = makeUserDefaults()

        let settings = UpdateSettings.load(from: userDefaults)

        XCTAssertTrue(settings.automaticallyChecksForUpdates)
    }

    func testPersistsAndRecoversEnabledValue() {
        let userDefaults = makeUserDefaults()

        UpdateSettings(automaticallyChecksForUpdates: true).save(to: userDefaults)

        XCTAssertTrue(UpdateSettings.load(from: userDefaults).automaticallyChecksForUpdates)
    }

    func testPersistsAndRecoversDisabledValue() {
        let userDefaults = makeUserDefaults()

        UpdateSettings(automaticallyChecksForUpdates: false).save(to: userDefaults)

        XCTAssertFalse(UpdateSettings.load(from: userDefaults).automaticallyChecksForUpdates)
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "MacMetricsViewTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }
}
