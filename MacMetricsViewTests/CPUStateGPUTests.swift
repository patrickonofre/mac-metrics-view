import XCTest
@testable import MacMetricsView

@MainActor
final class CPUStateGPUTests: XCTestCase {
    private func makeUserDefaults() -> UserDefaults {
        let suite = "gpu.state.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testUpdateWithGPUSampleStoresLatestAndHistory() {
        let state = CPUState(userDefaults: makeUserDefaults())

        state.update(with: GPUSample(utilizationPercent: 39))

        XCTAssertEqual(state.latestGPUSample?.utilizationPercent, 39)
        XCTAssertEqual(state.gpuHistory.samples.map(\.utilizationPercent), [39])
    }

    func testGPUSeverityReusesCPUThresholds() {
        let state = CPUState(userDefaults: makeUserDefaults())

        state.update(with: GPUSample(utilizationPercent: 79))
        XCTAssertEqual(state.gpuMenuBarTextStyle, .normal)

        state.update(with: GPUSample(utilizationPercent: 80))
        XCTAssertEqual(state.gpuMenuBarTextStyle, .elevatedCPU)

        state.update(with: GPUSample(utilizationPercent: 90))
        XCTAssertEqual(state.gpuMenuBarTextStyle, .highCPU)
    }

    func testGPUSegmentAppearsInMenuBarWhenVisible() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.setMetricIdentifierStyle(.labels)

        state.setGPUVisible(true)
        state.update(with: GPUSample(utilizationPercent: 39))

        XCTAssertTrue(state.menuBarTitle.contains("GPU"))
        XCTAssertTrue(state.menuBarTitle.contains("39%"))
    }

    func testGPUHiddenByDefaultOmitsSegment() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.setMetricIdentifierStyle(.labels)

        state.update(with: GPUSample(utilizationPercent: 39))

        // Default off (opt-in) → no GPU segment, even with a sample present.
        XCTAssertFalse(state.menuBarTitle.contains("GPU"))
    }

    func testGPUOnlyVisibleStillCountsAsVisibleMetric() {
        let state = CPUState(userDefaults: makeUserDefaults())

        state.setCPUVisible(false)
        state.setRAMVisible(false)
        state.setNetworkVisible(false)
        state.setGPUVisible(true)

        XCTAssertTrue(state.hasVisibleMetric)
    }

    func testHidingGPUFromMenuBarStillRecordsHistory() {
        let state = CPUState(userDefaults: makeUserDefaults())

        state.setGPUVisible(true)
        state.update(with: GPUSample(utilizationPercent: 40))
        state.setGPUVisible(false)
        state.update(with: GPUSample(utilizationPercent: 50))

        // Visibility only curates the menu bar; popover history keeps accumulating.
        XCTAssertEqual(state.gpuHistory.samples.map(\.utilizationPercent), [40, 50])
    }

    func testGPUVisibilityChangeNotifiesSamplerCoordinator() {
        let state = CPUState(userDefaults: makeUserDefaults())
        var changes: [(MetricVisibilitySettings.Metric, Bool)] = []
        state.onVisibilityChange = { metric, isVisible in
            changes.append((metric, isVisible))
        }

        state.setGPUVisible(true)
        state.setGPUVisible(false)

        XCTAssertEqual(changes.count, 2)
        XCTAssertEqual(changes[0].0, .gpu)
        XCTAssertTrue(changes[0].1)
        XCTAssertEqual(changes[1].0, .gpu)
        XCTAssertFalse(changes[1].1)
    }
}
