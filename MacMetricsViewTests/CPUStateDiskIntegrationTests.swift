import XCTest
@testable import MacMetricsView

@MainActor
final class CPUStateDiskIntegrationTests: XCTestCase {
    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "MacMetricsViewTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }

    private func makeSample(read: Double = 1_000, write: Double = 2_000) -> DiskSample {
        DiskSample(readBytesPerSecond: read, writeBytesPerSecond: write)
    }

    func testUpdateIsRecordedEvenWhileDiskHiddenFromMenuBar() {
        let state = CPUState(userDefaults: makeUserDefaults())
        // Disk defaults to hidden from the menu bar (ADR-005), but the popover still
        // shows it, so samples are recorded regardless of visibility.
        state.update(with: makeSample())

        XCTAssertEqual(state.latestDiskSample?.readBytesPerSecond, 1_000)
        XCTAssertEqual(state.diskHistory.samples.count, 1)
    }

    func testUpdatePublishesAndAppendsWhileVisible() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.setDiskVisible(true)

        state.update(with: makeSample(read: 1_500, write: 250))

        XCTAssertEqual(state.latestDiskSample?.readBytesPerSecond, 1_500)
        XCTAssertEqual(state.latestDiskSample?.writeBytesPerSecond, 250)
        XCTAssertEqual(state.diskHistory.samples.count, 1)
    }

    func testTogglingDiskMenuBarVisibilityKeepsSampleAndHistory() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(with: makeSample())
        state.setDiskVisible(true)
        state.setDiskVisible(false)

        // Visibility only curates the menu bar; the popover's data survives the toggle.
        XCTAssertEqual(state.latestDiskSample?.readBytesPerSecond, 1_000)
        XCTAssertEqual(state.diskHistory.samples.count, 1)
    }

    func testDiskSessionTotalsAccumulateFromConsecutiveSampleGaps() {
        let state = CPUState(userDefaults: makeUserDefaults())
        let t0 = Date(timeIntervalSince1970: 1_000)

        // First sample is the baseline — no previous timestamp, so it adds nothing.
        state.update(with: DiskSample(timestamp: t0, readBytesPerSecond: 1_000, writeBytesPerSecond: 500))
        XCTAssertEqual(state.diskSessionTotals.inbound, 0)
        XCTAssertEqual(state.diskSessionTotals.outbound, 0)

        // Second sample 2 s later: rate × elapsed folds into the running total.
        state.update(with: DiskSample(timestamp: t0.addingTimeInterval(2), readBytesPerSecond: 1_500, writeBytesPerSecond: 250))
        XCTAssertEqual(state.diskSessionTotals.inbound, 3_000)
        XCTAssertEqual(state.diskSessionTotals.outbound, 500)
    }

    func testSetDiskMenuBarMetricUpdatesDisplayAndFiresCallbackAndPersists() {
        let userDefaults = makeUserDefaults()
        let state = CPUState(userDefaults: userDefaults)
        var displayChangeCount = 0
        state.onDisplayChange = { displayChangeCount += 1 }

        state.setDiskMenuBarMetric(.split)

        XCTAssertEqual(state.diskMenuBarMetric, .split)
        XCTAssertEqual(displayChangeCount, 1)
        XCTAssertEqual(MetricDisplaySettings.load(from: userDefaults).diskMenuBarMetric, .split)

        // Idempotent: setting the same value again does not re-fire.
        state.setDiskMenuBarMetric(.split)
        XCTAssertEqual(displayChangeCount, 1)
    }

    func testVisibleMenuBarTitlesIncludesDiskSegmentWhenVisible() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.setMetricIdentifierStyle(.labels)
        state.setDiskVisible(true)
        state.update(with: makeSample())

        XCTAssertTrue(state.visibleMenuBarTitles.contains { $0.contains("DISK") })
    }

    func testAccessibilityMenuBarTitleIncludesDiskWordingWhenVisible() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.setDiskVisible(true)
        state.update(with: makeSample())

        XCTAssertTrue(state.accessibilityMenuBarTitle.contains(Strings.disk()))
    }

    func testDiskMenuBarTextStyleMatchesFormatter() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.setDiskVisible(true)
        // 900 MB/s combined → red (high).
        state.update(with: makeSample(read: 900 * 1_048_576, write: 0))

        XCTAssertEqual(state.diskMenuBarTextStyle, .highCPU)
        XCTAssertEqual(state.diskMenuBarTextStyle, DiskFormatter.menuBarTextStyle(for: state.latestDiskSample))
    }

    func testDiskCountsAsVisibleMetricWhenAloneEnabled() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.setCPUVisible(false)
        state.setRAMVisible(false)
        state.setNetworkVisible(false)
        state.setDiskVisible(true)

        XCTAssertTrue(state.hasVisibleMetric)
    }

    func testTogglingDiskNotifiesSamplerCoordinator() {
        let state = CPUState(userDefaults: makeUserDefaults())
        var changes: [(MetricVisibilitySettings.Metric, Bool)] = []
        state.onVisibilityChange = { metric, isVisible in
            changes.append((metric, isVisible))
        }

        state.setDiskVisible(true)
        state.setDiskVisible(false)

        XCTAssertEqual(changes.count, 2)
        XCTAssertEqual(changes[0].0, .disk)
        XCTAssertTrue(changes[0].1)
        XCTAssertEqual(changes[1].0, .disk)
        XCTAssertFalse(changes[1].1)
    }
}
