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
        state.metrics.update(with: makeSample())

        XCTAssertEqual(state.metrics.latestDiskSample?.readBytesPerSecond, 1_000)
        XCTAssertEqual(state.metrics.diskHistory.samples.count, 1)
    }

    func testUpdatePublishesAndAppendsWhileVisible() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.metrics.setDiskVisible(true)

        state.metrics.update(with: makeSample(read: 1_500, write: 250))

        XCTAssertEqual(state.metrics.latestDiskSample?.readBytesPerSecond, 1_500)
        XCTAssertEqual(state.metrics.latestDiskSample?.writeBytesPerSecond, 250)
        XCTAssertEqual(state.metrics.diskHistory.samples.count, 1)
    }

    func testTogglingDiskMenuBarVisibilityKeepsSampleAndHistory() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.metrics.update(with: makeSample())
        state.metrics.setDiskVisible(true)
        state.metrics.setDiskVisible(false)

        // Visibility only curates the menu bar; the popover's data survives the toggle.
        XCTAssertEqual(state.metrics.latestDiskSample?.readBytesPerSecond, 1_000)
        XCTAssertEqual(state.metrics.diskHistory.samples.count, 1)
    }

    func testDiskSessionTotalsAccumulateFromConsecutiveSampleGaps() {
        let state = CPUState(userDefaults: makeUserDefaults())
        let t0 = Date(timeIntervalSince1970: 1_000)

        // First sample is the baseline — no previous timestamp, so it adds nothing.
        state.metrics.update(with: DiskSample(timestamp: t0, readBytesPerSecond: 1_000, writeBytesPerSecond: 500))
        XCTAssertEqual(state.metrics.diskSessionTotals.inbound, 0)
        XCTAssertEqual(state.metrics.diskSessionTotals.outbound, 0)

        // Second sample 2 s later: rate × elapsed folds into the running total.
        state.metrics.update(with: DiskSample(timestamp: t0.addingTimeInterval(2), readBytesPerSecond: 1_500, writeBytesPerSecond: 250))
        XCTAssertEqual(state.metrics.diskSessionTotals.inbound, 3_000)
        XCTAssertEqual(state.metrics.diskSessionTotals.outbound, 500)
    }

    func testTrafficTotalsCountOnlyMeasuredIntervalsAcrossPause() throws {
        let state = CPUState(userDefaults: makeUserDefaults())
        let start = Date(timeIntervalSince1970: 1_000)
        for (offset, interval) in [(0.0, 3.0), (120.0, 1.0)] {
            let first = start.addingTimeInterval(offset)
            let last = first.addingTimeInterval(interval)
            state.metrics.update(with: try XCTUnwrap(NetworkSampleCalculator.sample(
                previous: NetworkCounterSnapshot(timestamp: first, receivedBytes: 1_000, sentBytes: 500),
                current: NetworkCounterSnapshot(timestamp: last, receivedBytes: 1_300, sentBytes: 650)
            )))
            state.metrics.update(with: try XCTUnwrap(DiskSampleCalculator.sample(
                previous: DiskCounterSnapshot(timestamp: first, bytesRead: 2_000, bytesWritten: 500),
                current: DiskCounterSnapshot(timestamp: last, bytesRead: 2_600, bytesWritten: 800)
            )))
        }

        XCTAssertEqual(state.metrics.networkSessionTotals.inbound, 600)
        XCTAssertEqual(state.metrics.networkSessionTotals.outbound, 300)
        XCTAssertEqual(state.metrics.diskSessionTotals.inbound, 1_200)
        XCTAssertEqual(state.metrics.diskSessionTotals.outbound, 600)

        let networkWindow = NetworkWindowStats.recentTotalBytes(in: state.metrics.networkHistory, interval: 3)
        XCTAssertEqual(networkWindow.download, 600)
        XCTAssertEqual(networkWindow.upload, 300)
        let diskWindow = DiskWindowStats.recentTotalBytes(in: state.metrics.diskHistory, interval: 3)
        XCTAssertEqual(diskWindow.read, 1_200)
        XCTAssertEqual(diskWindow.written, 600)
    }

    func testSetDiskMenuBarMetricUpdatesDisplayAndFiresCallbackAndPersists() {
        let userDefaults = makeUserDefaults()
        let state = CPUState(userDefaults: userDefaults)
        var displayChangeCount = 0
        state.onDisplayChange = { displayChangeCount += 1 }

        state.metrics.setDiskMenuBarMetric(.split)

        XCTAssertEqual(state.metrics.diskMenuBarMetric, .split)
        XCTAssertEqual(displayChangeCount, 1)
        XCTAssertEqual(MetricDisplaySettings.load(from: userDefaults).diskMenuBarMetric, .split)

        // Idempotent: setting the same value again does not re-fire.
        state.metrics.setDiskMenuBarMetric(.split)
        XCTAssertEqual(displayChangeCount, 1)
    }

    func testVisibleMenuBarTitlesIncludesDiskSegmentWhenVisible() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.metrics.setMetricIdentifierStyle(.labels)
        state.metrics.setDiskVisible(true)
        state.metrics.update(with: makeSample())

        XCTAssertTrue(state.visibleMenuBarTitles.contains { $0.contains("DISK") })
    }

    func testAccessibilityMenuBarTitleIncludesDiskWordingWhenVisible() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.metrics.setDiskVisible(true)
        state.metrics.update(with: makeSample())

        XCTAssertTrue(state.accessibilityMenuBarTitle.contains(Strings.disk()))
    }

    func testDiskMenuBarTextStyleMatchesFormatter() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.metrics.setDiskVisible(true)
        // 900 MB/s combined → red (high).
        state.metrics.update(with: makeSample(read: 900 * 1_048_576, write: 0))

        XCTAssertEqual(state.metrics.diskMenuBarTextStyle, .highCPU)
        XCTAssertEqual(state.metrics.diskMenuBarTextStyle, DiskFormatter.menuBarTextStyle(for: state.metrics.latestDiskSample))
    }

    func testDiskCountsAsVisibleMetricWhenAloneEnabled() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.metrics.setCPUVisible(false)
        state.metrics.setRAMVisible(false)
        state.metrics.setNetworkVisible(false)
        state.metrics.setDiskVisible(true)

        XCTAssertTrue(state.metrics.hasVisibleMetric)
    }

    func testTogglingDiskNotifiesSamplerCoordinator() {
        let state = CPUState(userDefaults: makeUserDefaults())
        var changes: [(MetricVisibilitySettings.Metric, Bool)] = []
        state.onVisibilityChange = { metric, isVisible in
            changes.append((metric, isVisible))
        }

        state.metrics.setDiskVisible(true)
        state.metrics.setDiskVisible(false)

        XCTAssertEqual(changes.count, 2)
        XCTAssertEqual(changes[0].0, .disk)
        XCTAssertTrue(changes[0].1)
        XCTAssertEqual(changes[1].0, .disk)
        XCTAssertFalse(changes[1].1)
    }
}
