import XCTest
@testable import MacMetricsView

@MainActor
final class LaunchAtLoginSettingsTests: XCTestCase {
    func testLaunchAtLoginStatusFormatsInPortuguese() {
        XCTAssertEqual(LaunchAtLoginStatus.enabled.localizedName(in: .portuguese), "Ativado")
        XCTAssertEqual(LaunchAtLoginStatus.disabled.localizedName(in: .portuguese), "Desativado")
        XCTAssertEqual(LaunchAtLoginStatus.unavailable.localizedName(in: .portuguese), "Indisponível")
        XCTAssertEqual(LaunchAtLoginStatus.error.localizedName(in: .portuguese), "Erro")
    }

    func testLaunchAtLoginStatusFormatsInEnglish() {
        XCTAssertEqual(LaunchAtLoginStatus.enabled.localizedName(in: .english), "Enabled")
        XCTAssertEqual(LaunchAtLoginStatus.disabled.localizedName(in: .english), "Disabled")
        XCTAssertEqual(LaunchAtLoginStatus.unavailable.localizedName(in: .english), "Unavailable")
        XCTAssertEqual(LaunchAtLoginStatus.error.localizedName(in: .english), "Error")
    }

    func testSettingsInitializeWithManagerStatus() {
        let settings = LaunchAtLoginSettings(manager: FakeLaunchAtLoginManager(status: .disabled))

        XCTAssertEqual(settings.status, .disabled)
        XCTAssertFalse(settings.isEnabled)
    }

    func testEnablingCallsManagerAndUpdatesStatus() {
        let manager = FakeLaunchAtLoginManager(status: .disabled)
        let settings = LaunchAtLoginSettings(manager: manager)

        settings.setEnabled(true)

        XCTAssertEqual(manager.setEnabledCalls, [true])
        XCTAssertEqual(settings.status, .enabled)
        XCTAssertTrue(settings.isEnabled)
        XCTAssertFalse(settings.showsError)
    }

    func testDisablingCallsManagerAndUpdatesStatus() {
        let manager = FakeLaunchAtLoginManager(status: .enabled)
        let settings = LaunchAtLoginSettings(manager: manager)

        settings.setEnabled(false)

        XCTAssertEqual(manager.setEnabledCalls, [false])
        XCTAssertEqual(settings.status, .disabled)
        XCTAssertFalse(settings.isEnabled)
        XCTAssertFalse(settings.showsError)
    }

    func testFailedEnableRevertsToRealKnownStatus() {
        let manager = FakeLaunchAtLoginManager(status: .disabled)
        manager.shouldThrow = true
        let settings = LaunchAtLoginSettings(manager: manager)

        settings.setEnabled(true)

        XCTAssertEqual(manager.setEnabledCalls, [true])
        XCTAssertEqual(settings.status, .disabled)
        XCTAssertFalse(settings.isEnabled)
        XCTAssertTrue(settings.showsError)
    }

    func testFailedDisableRevertsToRealKnownStatus() {
        let manager = FakeLaunchAtLoginManager(status: .enabled)
        manager.shouldThrow = true
        let settings = LaunchAtLoginSettings(manager: manager)

        settings.setEnabled(false)

        XCTAssertEqual(manager.setEnabledCalls, [false])
        XCTAssertEqual(settings.status, .enabled)
        XCTAssertTrue(settings.isEnabled)
        XCTAssertTrue(settings.showsError)
    }

    func testSystemStatusWinsOverCachedIntent() {
        let userDefaults = makeUserDefaults()
        userDefaults.set(true, forKey: "LaunchAtLoginSettings.intendedEnabled")
        let settings = LaunchAtLoginSettings(
            manager: FakeLaunchAtLoginManager(status: .disabled),
            userDefaults: userDefaults
        )

        XCTAssertEqual(settings.status, .disabled)
        XCTAssertFalse(settings.isEnabled)
    }

    func testRefreshReadsCurrentManagerStatusAndClearsError() {
        let manager = FakeLaunchAtLoginManager(status: .disabled)
        manager.shouldThrow = true
        let settings = LaunchAtLoginSettings(manager: manager)
        settings.setEnabled(true)
        manager.shouldThrow = false
        manager.currentStatus = .enabled

        settings.refresh()

        XCTAssertEqual(settings.status, .enabled)
        XCTAssertFalse(settings.showsError)
    }

    func testChangingLaunchAtLoginDoesNotChangeMetricSettingsOrNotifySamplerCoordinator() {
        let manager = FakeLaunchAtLoginManager(status: .disabled)
        let launchSettings = LaunchAtLoginSettings(manager: manager)
        let metricState = CPUState(userDefaults: makeUserDefaults())
        let originalVisibility = metricState.visibility
        let originalDisplay = metricState.display
        var visibilityChangeCount = 0
        var displayChangeCount = 0
        metricState.onVisibilityChange = { _, _ in visibilityChangeCount += 1 }
        metricState.onDisplayChange = { displayChangeCount += 1 }

        launchSettings.setEnabled(true)
        launchSettings.setEnabled(false)

        XCTAssertEqual(metricState.visibility, originalVisibility)
        XCTAssertEqual(metricState.display, originalDisplay)
        XCTAssertEqual(visibilityChangeCount, 0)
        XCTAssertEqual(displayChangeCount, 0)
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "MacMetricsViewTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }
}

private final class FakeLaunchAtLoginManager: LaunchAtLoginManaging {
    var currentStatus: LaunchAtLoginStatus
    var setEnabledCalls: [Bool] = []
    var shouldThrow = false

    init(status: LaunchAtLoginStatus) {
        currentStatus = status
    }

    var status: LaunchAtLoginStatus {
        currentStatus
    }

    func setEnabled(_ isEnabled: Bool) throws {
        setEnabledCalls.append(isEnabled)

        if shouldThrow {
            throw FakeError.failed
        }

        currentStatus = isEnabled ? .enabled : .disabled
    }

    private enum FakeError: Error {
        case failed
    }
}
