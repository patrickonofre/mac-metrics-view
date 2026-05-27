import XCTest
@testable import MacMetricsView

final class MetricVisibilitySettingsTests: XCTestCase {
    func testMetricDisplaySettingsDefaultToIcons() {
        let userDefaults = makeUserDefaults()

        let settings = MetricDisplaySettings.load(from: userDefaults)

        XCTAssertEqual(settings.identifierStyle, .icons)
    }

    func testMetricDisplaySettingsPersistChoices() {
        let userDefaults = makeUserDefaults()
        let settings = MetricDisplaySettings(identifierStyle: .labels)

        settings.save(to: userDefaults)

        XCTAssertEqual(MetricDisplaySettings.load(from: userDefaults), settings)
    }

    func testMetricDisplaySettingsMigrateLegacyLabelChoice() {
        let userDefaults = makeUserDefaults()
        userDefaults.set(true, forKey: "MetricDisplaySettings.showMetricLabels")

        let settings = MetricDisplaySettings.load(from: userDefaults)

        XCTAssertEqual(settings.identifierStyle, .labels)
    }

    func testRAMMenuBarMetricDefaultsToAppMemory() {
        let userDefaults = makeUserDefaults()

        let settings = MetricDisplaySettings.load(from: userDefaults)

        XCTAssertEqual(settings.ramMenuBarMetric, .appMemory)
    }

    func testRAMMenuBarMetricPersistsBothValues() {
        for metric in [MetricDisplaySettings.RAMMenuBarMetric.appMemory, .pressure] {
            let userDefaults = makeUserDefaults()
            let settings = MetricDisplaySettings(ramMenuBarMetric: metric)

            settings.save(to: userDefaults)

            XCTAssertEqual(MetricDisplaySettings.load(from: userDefaults).ramMenuBarMetric, metric)
        }
    }

    func testRAMMenuBarMetricFallsBackToAppMemoryOnGarbageValue() {
        let userDefaults = makeUserDefaults()
        userDefaults.set("nonsense", forKey: "MetricDisplaySettings.ramMenuBarMetric")

        let settings = MetricDisplaySettings.load(from: userDefaults)

        XCTAssertEqual(settings.ramMenuBarMetric, .appMemory)
    }

    func testVisibilitySettingsDefaultToAllMetricsVisible() {
        let userDefaults = makeUserDefaults()

        let settings = MetricVisibilitySettings.load(from: userDefaults)

        XCTAssertTrue(settings.showCPU)
        XCTAssertTrue(settings.showRAM)
        XCTAssertTrue(settings.showNetwork)
        XCTAssertFalse(settings.showTemperature)
    }

    func testVisibilitySettingsPersistChoices() {
        let userDefaults = makeUserDefaults()
        let settings = MetricVisibilitySettings(showCPU: false, showRAM: true, showNetwork: false, showTemperature: true)

        settings.save(to: userDefaults)

        XCTAssertEqual(MetricVisibilitySettings.load(from: userDefaults), settings)
    }

    @MainActor
    func testHidingCPURemovesCPUFromFormattedMenuBarOutput() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.setMetricIdentifierStyle(.labels)

        state.setCPUVisible(false)

        XCTAssertFalse(state.menuBarTitle.contains("CPU"))
        XCTAssertTrue(state.menuBarTitle.contains("RAM"))
        XCTAssertTrue(state.menuBarTitle.contains("NET"))
    }

    @MainActor
    func testHidingRAMRemovesRAMFromFormattedMenuBarOutput() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.setMetricIdentifierStyle(.labels)

        state.setRAMVisible(false)

        XCTAssertTrue(state.menuBarTitle.contains("CPU"))
        XCTAssertFalse(state.menuBarTitle.contains("RAM"))
        XCTAssertTrue(state.menuBarTitle.contains("NET"))
    }

    @MainActor
    func testRAMMenuBarMetricSelectionDrivesTitleAndPersists() {
        let userDefaults = makeUserDefaults()
        let state = CPUState(userDefaults: userDefaults)
        state.setMetricIdentifierStyle(.labels)
        state.update(with: RAMSample(usedGB: 14, totalGB: 16, usedPercent: 87, appMemoryGB: 12.4, appMemoryPercent: 77, pressurePercent: 58.6))

        // Default: App Memory → GB.
        XCTAssertTrue(state.menuBarTitle.contains("RAM 12.4 GB"))

        state.setRAMMenuBarMetric(.pressure)
        XCTAssertTrue(state.menuBarTitle.contains("RAM 59%"))
        XCTAssertFalse(state.menuBarTitle.contains("GB"))

        // Persisted across a fresh load.
        XCTAssertEqual(MetricDisplaySettings.load(from: userDefaults).ramMenuBarMetric, .pressure)
        let reloaded = CPUState(userDefaults: userDefaults)
        XCTAssertEqual(reloaded.ramMenuBarMetric, .pressure)
    }

    @MainActor
    func testHidingNetworkRemovesNetworkFromFormattedMenuBarOutput() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.setMetricIdentifierStyle(.labels)

        state.setNetworkVisible(false)

        XCTAssertTrue(state.menuBarTitle.contains("CPU"))
        XCTAssertTrue(state.menuBarTitle.contains("RAM"))
        XCTAssertFalse(state.menuBarTitle.contains("NET"))
    }

    @MainActor
    func testAllMetricsHiddenReturnsMinimalMenuBarControlLabel() {
        let state = CPUState(userDefaults: makeUserDefaults())

        state.setCPUVisible(false)
        state.setRAMVisible(false)
        state.setNetworkVisible(false)

        XCTAssertEqual(state.menuBarTitle, Strings.metricsPlaceholder())
    }

    @MainActor
    func testTemperatureCountsAsVisibleMetric() {
        let state = CPUState(userDefaults: makeUserDefaults())

        state.setCPUVisible(false)
        state.setRAMVisible(false)
        state.setNetworkVisible(false)
        state.setTemperatureVisible(true)

        XCTAssertTrue(state.hasVisibleMetric)
        XCTAssertEqual(state.menuBarTitle, "--")
    }

    @MainActor
    func testHidingMetricPreventsNewHistorySamples() {
        let state = CPUState(userDefaults: makeUserDefaults())

        state.setCPUVisible(false)
        state.update(with: CPUSample(totalUsagePercent: 42))

        XCTAssertTrue(state.history.samples.isEmpty)
    }

    @MainActor
    func testShowingHiddenMetricResetsToFallbackState() {
        let state = CPUState(userDefaults: makeUserDefaults())

        state.update(with: CPUSample(totalUsagePercent: 42))
        state.setCPUVisible(false)
        state.setCPUVisible(true)

        XCTAssertEqual(state.menuBarTitle, " --%  -- GB  ↓ --.- MB/s ↑ --.- MB/s")
        XCTAssertTrue(state.history.samples.isEmpty)
    }

    @MainActor
    func testIconDisplayModeOmitsMetricLabelsFromMenuBarOutput() {
        let state = CPUState(userDefaults: makeUserDefaults())

        XCTAssertEqual(state.menuBarTitle, " --%  -- GB  ↓ --.- MB/s ↑ --.- MB/s")
        XCTAssertFalse(state.menuBarTitle.contains("CPU"))
        XCTAssertFalse(state.menuBarTitle.contains("RAM"))
        XCTAssertFalse(state.menuBarTitle.contains("NET"))
    }

    @MainActor
    func testTemperatureMenuBarOutputUsesIconModeWithoutLabel() throws {
        let state = CPUState(userDefaults: makeUserDefaults())

        state.setCPUVisible(false)
        state.setRAMVisible(false)
        state.setNetworkVisible(false)
        state.setTemperatureVisible(true)
        state.update(with: try XCTUnwrap(TemperatureSample(celsius: 68.4, state: .normal)))

        XCTAssertEqual(state.menuBarTitle, "68 °C")
        XCTAssertFalse(state.menuBarTitle.contains("TEMP"))
    }

    @MainActor
    func testTemperatureMenuBarOutputUsesTempLabelInLabelMode() throws {
        let state = CPUState(userDefaults: makeUserDefaults())

        state.setMetricIdentifierStyle(.labels)
        state.setCPUVisible(false)
        state.setRAMVisible(false)
        state.setNetworkVisible(false)
        state.setTemperatureVisible(true)
        state.update(with: try XCTUnwrap(TemperatureSample(celsius: nil, state: .normal)))

        XCTAssertEqual(state.menuBarTitle, "TEMP Normal")
    }

    @MainActor
    func testHidingTemperatureRemovesSegmentAndPreventsHistory() throws {
        let state = CPUState(userDefaults: makeUserDefaults())

        state.setCPUVisible(false)
        state.setRAMVisible(false)
        state.setNetworkVisible(false)
        state.setTemperatureVisible(true)
        state.update(with: try XCTUnwrap(TemperatureSample(celsius: 68, state: .normal)))
        state.setTemperatureVisible(false)
        state.update(with: try XCTUnwrap(TemperatureSample(celsius: 69, state: .normal)))

        XCTAssertEqual(state.menuBarTitle, Strings.metricsPlaceholder())
        XCTAssertEqual(state.temperatureHistory.samples.map(\.celsius), [68])
    }

    @MainActor
    func testIconDisplayModeKeepsAccessibilityLabelExplicit() {
        let state = CPUState(userDefaults: makeUserDefaults())

        XCTAssertEqual(state.accessibilityMenuBarTitle, "CPU --%, RAM -- GB, NET ↓ --.- MB/s ↑ --.- MB/s")
    }

    @MainActor
    func testLabelDisplayModeIncludesMetricLabelsForVisibleMetrics() {
        let state = CPUState(userDefaults: makeUserDefaults())

        state.setMetricIdentifierStyle(.labels)

        XCTAssertEqual(state.menuBarTitle, "CPU  --%  RAM -- GB  NET ↓ --.- MB/s ↑ --.- MB/s")
    }

    @MainActor
    func testChangingIdentifierStyleDoesNotNotifySamplerCoordinator() {
        let state = CPUState(userDefaults: makeUserDefaults())
        var visibilityChanges: [(MetricVisibilitySettings.Metric, Bool)] = []
        var displayChangeCount = 0
        state.onVisibilityChange = { metric, isVisible in
            visibilityChanges.append((metric, isVisible))
        }
        state.onDisplayChange = {
            displayChangeCount += 1
        }

        state.setMetricIdentifierStyle(.labels)
        state.setMetricIdentifierStyle(.icons)

        XCTAssertTrue(visibilityChanges.isEmpty)
        XCTAssertEqual(displayChangeCount, 2)
    }

    @MainActor
    func testChangingVisibilityNotifiesSamplerCoordinator() {
        let state = CPUState(userDefaults: makeUserDefaults())
        var changes: [(MetricVisibilitySettings.Metric, Bool)] = []
        state.onVisibilityChange = { metric, isVisible in
            changes.append((metric, isVisible))
        }

        state.setNetworkVisible(false)
        state.setNetworkVisible(true)
        state.setTemperatureVisible(true)
        state.setTemperatureVisible(false)

        XCTAssertEqual(changes.count, 4)
        XCTAssertEqual(changes[0].0, .network)
        XCTAssertFalse(changes[0].1)
        XCTAssertEqual(changes[1].0, .network)
        XCTAssertTrue(changes[1].1)
        XCTAssertEqual(changes[2].0, .temperature)
        XCTAssertTrue(changes[2].1)
        XCTAssertEqual(changes[3].0, .temperature)
        XCTAssertFalse(changes[3].1)
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "MacMetricsViewTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }
}
