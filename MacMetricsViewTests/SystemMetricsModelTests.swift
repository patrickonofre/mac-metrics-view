import XCTest
@testable import MacMetricsView

/// Direct tests for `SystemMetricsModel` extracted from `CPUState` (task-005, the final
/// pillar). Exercises the model standalone (no `CPUState`).
@MainActor
final class SystemMetricsModelTests: XCTestCase {
    private struct StubBatteryReader: BatteryReading {
        let sample: BatterySample?
        func readSample() -> BatterySample? { sample }
    }

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "SystemMetricsModelTests.\(UUID().uuidString)")!
    }

    private func makeModel(
        userDefaults: UserDefaults? = nil,
        processReader: ProcessReading = FakeProcessReader(),
        batteryReader: BatteryReading = StubBatteryReader(sample: nil)
    ) -> SystemMetricsModel {
        SystemMetricsModel(
            userDefaults: userDefaults ?? makeDefaults(),
            processReader: processReader,
            samplingExecutor: InlineSamplingExecutor(),
            batteryReader: batteryReader
        )
    }

    func testUpdateWithCPUSamplePublishesLatestAndAppendsHistory() {
        let model = makeModel()
        let sample = CPUSample(totalUsagePercent: 42)

        model.update(with: sample)

        XCTAssertEqual(model.latestSample?.totalUsagePercent, 42)
        XCTAssertEqual(model.history.samples.count, 1)
    }

    func testSetCPUVisiblePersistsAndFiresCallback() {
        let defaults = makeDefaults()
        let model = makeModel(userDefaults: defaults)
        var changed: (MetricVisibilitySettings.Metric, Bool)?
        model.onVisibilityChange = { metric, isVisible in changed = (metric, isVisible) }

        model.setCPUVisible(false)

        XCTAssertFalse(model.visibility.showCPU)
        XCTAssertEqual(changed?.0, .cpu)
        XCTAssertEqual(changed?.1, false)
        XCTAssertFalse(MetricVisibilitySettings.load(from: defaults).showCPU)
    }

    func testSetCPUVisibleIsNoOpWhenUnchanged() {
        let model = makeModel()
        var fireCount = 0
        model.onVisibilityChange = { _, _ in fireCount += 1 }

        model.setCPUVisible(true)   // already true by default

        XCTAssertEqual(fireCount, 0)
    }

    func testSetUpdateRateClampsToValidValuesAndPersists() {
        let defaults = makeDefaults()
        let model = makeModel(userDefaults: defaults)

        model.setUpdateRate(2)
        XCTAssertEqual(model.updateRate, 2)
        XCTAssertEqual(MetricDisplaySettings.resolved(from: defaults).updateRate, 2)

        model.setUpdateRate(99)   // invalid → clamps to 1
        XCTAssertEqual(model.updateRate, 1)
    }

    func testReplaceDisplayPersistsAndRepublishes() {
        let defaults = makeDefaults()
        let model = makeModel(userDefaults: defaults)
        var newDisplay = model.display
        newDisplay.tokenScope = .session

        model.replaceDisplay(newDisplay)

        XCTAssertEqual(model.display.tokenScope, .session)
        XCTAssertEqual(MetricDisplaySettings.resolved(from: defaults).tokenScope, .session)
    }

    func testRefreshBatteryReadingPublishesLatestSample() {
        let sample = BatterySample(
            chargePercent: 80,
            powerSource: .ac,
            isCharging: true,
            timeRemaining: 3600,
            healthCondition: .normal,
            cycleCount: 10
        )
        let model = makeModel(batteryReader: StubBatteryReader(sample: sample))

        XCTAssertNil(model.latestBatterySample)
        model.refreshBatteryReading()
        XCTAssertEqual(model.latestBatterySample?.chargePercent, 80)
    }

    func testProcessSamplingLifecycleIsIdempotentAndStoppable() {
        let reader = FakeProcessReader()
        let model = makeModel(processReader: reader)

        model.beginProcessSampling()
        XCTAssertEqual(reader.readCount, 1)

        model.beginProcessSampling()   // idempotent
        XCTAssertEqual(reader.readCount, 1)

        model.endProcessSampling()
        XCTAssertTrue(model.topCPUProcesses.isEmpty)
    }
}
