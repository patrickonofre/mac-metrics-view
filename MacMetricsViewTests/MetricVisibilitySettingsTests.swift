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

    func testVisibilitySettingsDefaultToAllMetricsVisible() {
        let userDefaults = makeUserDefaults()

        let settings = MetricVisibilitySettings.load(from: userDefaults)

        XCTAssertTrue(settings.showCPU)
        XCTAssertTrue(settings.showRAM)
        XCTAssertTrue(settings.showNetwork)
        XCTAssertFalse(settings.showTemperature)
        XCTAssertFalse(settings.showDisk)
    }

    func testVisibilitySettingsPersistChoices() {
        let userDefaults = makeUserDefaults()
        let settings = MetricVisibilitySettings(
            showCPU: false,
            showRAM: true,
            showNetwork: false,
            showTemperature: true,
            showDisk: true
        )

        settings.save(to: userDefaults)

        XCTAssertEqual(MetricVisibilitySettings.load(from: userDefaults), settings)
    }

    func testDiskVisibilityDefaultsToFalseWhenKeyAbsent() {
        let userDefaults = makeUserDefaults()

        let settings = MetricVisibilitySettings.load(from: userDefaults)

        XCTAssertFalse(settings.showDisk)
    }

    func testDiskVisibilityRoundTripsThroughPersistence() {
        let userDefaults = makeUserDefaults()
        let settings = MetricVisibilitySettings(showDisk: true)

        settings.save(to: userDefaults)

        XCTAssertTrue(MetricVisibilitySettings.load(from: userDefaults).showDisk)
    }

    func testHasVisibleMetricRespectsDiskOnly() {
        var settings = MetricVisibilitySettings(
            showCPU: false,
            showRAM: false,
            showNetwork: false,
            showTemperature: false,
            showDisk: true
        )
        XCTAssertTrue(settings.hasVisibleMetric)

        settings.showDisk = false
        XCTAssertFalse(settings.hasVisibleMetric)
    }

    func testFreshInstallAppliesFirstRunPreset() {
        let userDefaults = makeUserDefaults()

        let settings = MetricVisibilitySettings.resolved(from: userDefaults, isFreshInstall: true)

        XCTAssertEqual(settings, MetricVisibilitySettings.firstRunPreset)
        XCTAssertTrue(settings.showCPU)
        XCTAssertTrue(settings.showRAM)
        XCTAssertTrue(settings.showTemperature)
        XCTAssertFalse(settings.showNetwork)
        XCTAssertFalse(settings.showDisk)
        // Persisted so later loads return the preset, not the legacy defaults.
        XCTAssertEqual(MetricVisibilitySettings.load(from: userDefaults), MetricVisibilitySettings.firstRunPreset)
    }

    func testExistingInstallKeepsLegacyDefaultsInsteadOfPreset() {
        let userDefaults = makeUserDefaults()

        let settings = MetricVisibilitySettings.resolved(from: userDefaults, isFreshInstall: false)

        // No silent menu-bar change on update: Network stays on, Temperature stays off.
        XCTAssertTrue(settings.showNetwork)
        XCTAssertFalse(settings.showTemperature)
        XCTAssertFalse(settings.showDisk)
    }

    func testResolvedHonorsStoredVisibilityEvenWhenFresh() {
        let userDefaults = makeUserDefaults()
        MetricVisibilitySettings(
            showCPU: false,
            showRAM: true,
            showNetwork: true,
            showTemperature: false,
            showDisk: true
        ).save(to: userDefaults)

        let settings = MetricVisibilitySettings.resolved(from: userDefaults, isFreshInstall: true)

        // User's stored choice wins over the preset.
        XCTAssertFalse(settings.showCPU)
        XCTAssertTrue(settings.showNetwork)
        XCTAssertTrue(settings.showDisk)
    }

    func testFirstRunPresetAppliedOnlyOnceThenUserSelectionWins() {
        let userDefaults = makeUserDefaults()

        _ = MetricVisibilitySettings.resolved(from: userDefaults, isFreshInstall: true)

        // User reconfigures: turns Network on.
        var chosen = MetricVisibilitySettings.load(from: userDefaults)
        chosen.showNetwork = true
        chosen.save(to: userDefaults)

        let reResolved = MetricVisibilitySettings.resolved(from: userDefaults, isFreshInstall: true)

        XCTAssertTrue(reResolved.showNetwork, "preset must not be re-applied after the user reconfigures")
        XCTAssertEqual(reResolved, chosen)
    }

    @MainActor
    func testHidingCPURemovesCPUFromFormattedMenuBarOutput() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.metrics.setMetricIdentifierStyle(.labels)

        state.metrics.setCPUVisible(false)

        XCTAssertFalse(state.menuBarTitle.contains("CPU"))
        XCTAssertTrue(state.menuBarTitle.contains("RAM"))
        XCTAssertTrue(state.menuBarTitle.contains("NET"))
    }

    @MainActor
    func testHidingRAMRemovesRAMFromFormattedMenuBarOutput() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.metrics.setMetricIdentifierStyle(.labels)

        state.metrics.setRAMVisible(false)

        XCTAssertTrue(state.menuBarTitle.contains("CPU"))
        XCTAssertFalse(state.menuBarTitle.contains("RAM"))
        XCTAssertTrue(state.menuBarTitle.contains("NET"))
    }

    @MainActor
    func testLegacyRAMMenuBarMetricPreferenceDoesNotDriveTitle() {
        let userDefaults = makeUserDefaults()
        userDefaults.set("pressure", forKey: "MetricDisplaySettings.ramMenuBarMetric")
        let state = CPUState(userDefaults: userDefaults)
        state.metrics.setMetricIdentifierStyle(.labels)
        state.metrics.update(with: RAMSample(usedGB: 14, totalGB: 16, usedPercent: 87, appMemoryGB: 12.4, appMemoryPercent: 77, pressurePercent: 58.6))

        XCTAssertTrue(state.menuBarTitle.contains("RAM 14.0/16 GB"))
        XCTAssertFalse(state.menuBarTitle.contains("59%"))
        XCTAssertTrue(state.accessibilityMenuBarTitle.contains("RAM 14.0/16 GB"))
    }

    @MainActor
    func testHidingNetworkRemovesNetworkFromFormattedMenuBarOutput() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.metrics.setMetricIdentifierStyle(.labels)

        state.metrics.setNetworkVisible(false)

        XCTAssertTrue(state.menuBarTitle.contains("CPU"))
        XCTAssertTrue(state.menuBarTitle.contains("RAM"))
        XCTAssertFalse(state.menuBarTitle.contains("NET"))
    }

    @MainActor
    func testAllMetricsHiddenReturnsMinimalMenuBarControlLabel() {
        let state = CPUState(userDefaults: makeUserDefaults())

        state.metrics.setCPUVisible(false)
        state.metrics.setRAMVisible(false)
        state.metrics.setNetworkVisible(false)

        XCTAssertEqual(state.menuBarTitle, Strings.metricsPlaceholder())
    }

    @MainActor
    func testTemperatureCountsAsVisibleMetric() {
        let state = CPUState(userDefaults: makeUserDefaults())

        state.metrics.setCPUVisible(false)
        state.metrics.setRAMVisible(false)
        state.metrics.setNetworkVisible(false)
        state.metrics.setTemperatureVisible(true)

        XCTAssertTrue(state.metrics.hasVisibleMetric)
        XCTAssertEqual(state.menuBarTitle, "--")
    }

    @MainActor
    func testHidingMetricFromMenuBarStillRecordsHistory() {
        let state = CPUState(userDefaults: makeUserDefaults())

        state.metrics.setCPUVisible(false)
        state.metrics.update(with: CPUSample(totalUsagePercent: 42))

        // Visibility only curates the menu bar; the popover shows every metric, so history
        // keeps accumulating even when hidden from the menu bar.
        XCTAssertEqual(state.metrics.latestSample?.totalUsagePercent, 42)
        XCTAssertEqual(state.metrics.history.samples.count, 1)
    }

    @MainActor
    func testTogglingMenuBarVisibilityKeepsExistingData() {
        let state = CPUState(userDefaults: makeUserDefaults())

        state.metrics.update(with: CPUSample(totalUsagePercent: 42))
        state.metrics.setCPUVisible(false)
        state.metrics.setCPUVisible(true)

        // No reset on re-show: the sample and history survive a menu-bar visibility toggle.
        XCTAssertEqual(state.metrics.latestSample?.totalUsagePercent, 42)
        XCTAssertEqual(state.metrics.history.samples.count, 1)
    }

    @MainActor
    func testIconDisplayModeOmitsMetricLabelsFromMenuBarOutput() {
        let state = CPUState(userDefaults: makeUserDefaults())

        XCTAssertEqual(state.menuBarTitle, " --%  --/-- GB  ↓ --.- MB/s ↑ --.- MB/s")
        XCTAssertFalse(state.menuBarTitle.contains("CPU"))
        XCTAssertFalse(state.menuBarTitle.contains("RAM"))
        XCTAssertFalse(state.menuBarTitle.contains("NET"))
    }

    @MainActor
    func testTemperatureMenuBarOutputUsesIconModeWithoutLabel() throws {
        let state = CPUState(userDefaults: makeUserDefaults())

        state.metrics.setCPUVisible(false)
        state.metrics.setRAMVisible(false)
        state.metrics.setNetworkVisible(false)
        state.metrics.setTemperatureVisible(true)
        state.metrics.update(with: try XCTUnwrap(TemperatureSample(celsius: 68.4, state: .normal)))

        XCTAssertEqual(state.menuBarTitle, "68 °C")
        XCTAssertFalse(state.menuBarTitle.contains("TEMP"))
    }

    @MainActor
    func testTemperatureMenuBarOutputUsesTempLabelInLabelMode() throws {
        let state = CPUState(userDefaults: makeUserDefaults())

        state.metrics.setMetricIdentifierStyle(.labels)
        state.metrics.setCPUVisible(false)
        state.metrics.setRAMVisible(false)
        state.metrics.setNetworkVisible(false)
        state.metrics.setTemperatureVisible(true)
        state.metrics.update(with: try XCTUnwrap(TemperatureSample(celsius: nil, state: .normal)))

        XCTAssertEqual(state.menuBarTitle, "TEMP Normal")
    }

    @MainActor
    func testHidingTemperatureRemovesMenuBarSegmentButKeepsHistory() throws {
        let state = CPUState(userDefaults: makeUserDefaults())

        state.metrics.setCPUVisible(false)
        state.metrics.setRAMVisible(false)
        state.metrics.setNetworkVisible(false)
        state.metrics.setTemperatureVisible(true)
        state.metrics.update(with: try XCTUnwrap(TemperatureSample(celsius: 68, state: .normal)))
        state.metrics.setTemperatureVisible(false)
        state.metrics.update(with: try XCTUnwrap(TemperatureSample(celsius: 69, state: .normal)))

        // Menu bar: temperature hidden, and it was the only visible metric → placeholder.
        XCTAssertEqual(state.menuBarTitle, Strings.metricsPlaceholder())
        // Popover data: history keeps accumulating regardless of menu-bar visibility.
        XCTAssertEqual(state.metrics.temperatureHistory.samples.map(\.celsius), [68, 69])
    }

    @MainActor
    func testIconDisplayModeKeepsAccessibilityLabelExplicit() {
        let state = CPUState(userDefaults: makeUserDefaults())

        XCTAssertEqual(state.accessibilityMenuBarTitle, "CPU --%, RAM --/-- GB, NET ↓ --.- MB/s ↑ --.- MB/s")
    }

    @MainActor
    func testLabelDisplayModeIncludesMetricLabelsForVisibleMetrics() {
        let state = CPUState(userDefaults: makeUserDefaults())

        state.metrics.setMetricIdentifierStyle(.labels)

        XCTAssertEqual(state.menuBarTitle, "CPU  --%  RAM --/-- GB  NET ↓ --.- MB/s ↑ --.- MB/s")
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

        state.metrics.setMetricIdentifierStyle(.labels)
        state.metrics.setMetricIdentifierStyle(.icons)

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

        state.metrics.setNetworkVisible(false)
        state.metrics.setNetworkVisible(true)
        state.metrics.setTemperatureVisible(true)
        state.metrics.setTemperatureVisible(false)

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
