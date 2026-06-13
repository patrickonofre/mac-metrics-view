import XCTest
@testable import MacMetricsView

final class BatteryVisibilitySettingsTests: XCTestCase {
    private func makeUserDefaults() -> UserDefaults {
        let suite = "battery.visibility.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testBatteryHiddenByDefault() {
        let defaults = makeUserDefaults()
        XCTAssertFalse(MetricVisibilitySettings.load(from: defaults).showBattery)
    }

    func testBatteryVisibilityRoundTrips() {
        let defaults = makeUserDefaults()
        MetricVisibilitySettings(showBattery: true).save(to: defaults)
        XCTAssertTrue(MetricVisibilitySettings.load(from: defaults).showBattery)
    }

    func testFirstRunPresetKeepsBatteryOff() {
        XCTAssertFalse(MetricVisibilitySettings.firstRunPreset.showBattery)
    }

    func testFreshInstallResolvesBatteryOff() {
        let defaults = makeUserDefaults()
        let resolved = MetricVisibilitySettings.resolved(from: defaults, isFreshInstall: true)
        XCTAssertFalse(resolved.showBattery)
    }

    func testUpgradeResolvesBatteryOff() {
        let defaults = makeUserDefaults()
        let resolved = MetricVisibilitySettings.resolved(from: defaults, isFreshInstall: false)
        XCTAssertFalse(resolved.showBattery)
    }

    func testBatteryOnlyCountsAsVisibleMetric() {
        let settings = MetricVisibilitySettings(showCPU: false, showRAM: false, showNetwork: false, showBattery: true)
        XCTAssertTrue(settings.hasVisibleMetric)
    }

    func testAddingBatteryDoesNotChangeExistingDefaults() {
        let defaults = makeUserDefaults()
        let settings = MetricVisibilitySettings.load(from: defaults)
        XCTAssertTrue(settings.showCPU)
        XCTAssertTrue(settings.showRAM)
    }
}
