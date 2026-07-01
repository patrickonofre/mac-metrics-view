import XCTest
@testable import MacMetricsView

final class GPUVisibilitySettingsTests: XCTestCase {
    private func makeUserDefaults() -> UserDefaults {
        let suite = "gpu.visibility.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testGPUHiddenByDefault() {
        let defaults = makeUserDefaults()
        XCTAssertFalse(MetricVisibilitySettings.load(from: defaults).showGPU)
    }

    func testGPUVisibilityRoundTrips() {
        let defaults = makeUserDefaults()
        MetricVisibilitySettings(showGPU: true).save(to: defaults)
        XCTAssertTrue(MetricVisibilitySettings.load(from: defaults).showGPU)
    }

    func testFirstRunPresetKeepsGPUOff() {
        XCTAssertFalse(MetricVisibilitySettings.firstRunPreset.showGPU)
    }

    func testFreshInstallResolvesGPUOff() {
        let defaults = makeUserDefaults()
        let resolved = MetricVisibilitySettings.resolved(from: defaults, isFreshInstall: true)
        XCTAssertFalse(resolved.showGPU)
    }

    /// The opt-in guarantee: an existing user updating the app gets no new GPU segment
    /// in their menu bar (no silent layout shift on update).
    func testUpgradeResolvesGPUOff() {
        let defaults = makeUserDefaults()
        let resolved = MetricVisibilitySettings.resolved(from: defaults, isFreshInstall: false)
        XCTAssertFalse(resolved.showGPU)
    }

    func testGPUOnlyCountsAsVisibleMetric() {
        let settings = MetricVisibilitySettings(showCPU: false, showRAM: false, showNetwork: false, showGPU: true)
        XCTAssertTrue(settings.hasVisibleMetric)
    }

    func testAddingGPUDoesNotChangeExistingDefaults() {
        let defaults = makeUserDefaults()
        let settings = MetricVisibilitySettings.load(from: defaults)
        XCTAssertTrue(settings.showCPU)
        XCTAssertTrue(settings.showRAM)
    }
}
