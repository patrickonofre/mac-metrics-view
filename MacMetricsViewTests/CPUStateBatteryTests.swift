import XCTest
@testable import MacMetricsView

@MainActor
final class CPUStateBatteryTests: XCTestCase {
    private struct StubBatteryReader: BatteryReading {
        let sample: BatterySample?
        func readSample() -> BatterySample? { sample }
    }

    private func makeState(batteryReader: BatteryReading = StubBatteryReader(sample: nil)) -> CPUState {
        let suiteName = "MacMetricsViewTests.CPUStateBattery.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        ud.removePersistentDomain(forName: suiteName)
        return CPUState(
            userDefaults: ud,
            accessibilityAuthorization: FakeAccessibilityAuthorization(isTrusted: false),
            batteryReader: batteryReader
        )
    }

    private func sample(charge: Int, charging: Bool = false) -> BatterySample {
        BatterySample(chargePercent: charge, powerSource: .battery, isCharging: charging, timeRemaining: 3600, healthCondition: .normal, cycleCount: 10)
    }

    func testUpdatePublishesSample() {
        let state = makeState()
        let s = sample(charge: 80)
        state.metrics.update(with: s)
        XCTAssertEqual(state.metrics.latestBatterySample, s)
    }

    func testTitleShownWhenVisibleAndSamplePresent() {
        let state = makeState()
        state.metrics.setBatteryVisible(true)
        state.metrics.update(with: sample(charge: 82))
        XCTAssertTrue(state.visibleMenuBarTitles.contains("82%"))
    }

    func testTitleHiddenWhenToggledOff() {
        let state = makeState()
        // showBattery defaults false
        state.metrics.update(with: sample(charge: 82))
        XCTAssertFalse(state.visibleMenuBarTitles.contains("82%"))
    }

    func testTitleHiddenWhenNoSampleEvenIfVisible() {
        let state = makeState()
        state.metrics.setBatteryVisible(true)
        // no sample → segment omitted (ADR-003: desktop / no battery)
        XCTAssertFalse(state.visibleMenuBarTitles.contains("--"))
    }

    func testTextStyleReflectsLowCharge() {
        let state = makeState()
        state.metrics.update(with: sample(charge: 8))
        XCTAssertEqual(state.metrics.batteryMenuBarTextStyle, .highCPU)
    }

    func testSetBatteryVisiblePersistsAndFiresCallback() {
        let state = makeState()
        var captured: (MetricVisibilitySettings.Metric, Bool)?
        state.onVisibilityChange = { metric, isVisible in captured = (metric, isVisible) }

        state.metrics.setBatteryVisible(true)

        XCTAssertTrue(state.metrics.visibility.showBattery)
        XCTAssertEqual(captured?.0, .battery)
        XCTAssertEqual(captured?.1, true)
    }

    func testRowValueIsNoBatteryWhenNil() {
        let state = makeState()
        XCTAssertEqual(state.metrics.batteryRowValue, Strings.batteryNoBattery())
    }

    func testDetailRowsPresentWithSampleEmptyWithout() {
        let state = makeState()
        XCTAssertTrue(state.metrics.batteryDetailRows.isEmpty)
        state.metrics.update(with: sample(charge: 50))
        XCTAssertFalse(state.metrics.batteryDetailRows.isEmpty)
    }

    // Regression: with the menu-bar toggle off the continuous sampler never runs, so the
    // popover row must still go live via the one-shot read on open (bug: showed
    // "no battery" on a battery-equipped Mac while hidden).
    func testRefreshBatteryReadingPopulatesFromReaderWhenToggleOff() {
        let state = makeState(batteryReader: StubBatteryReader(sample: sample(charge: 73)))
        XCTAssertFalse(state.metrics.visibility.showBattery)   // hidden, sampler never started
        XCTAssertNil(state.metrics.latestBatterySample)

        state.metrics.refreshBatteryReading()

        XCTAssertEqual(state.metrics.latestBatterySample?.chargePercent, 73)
        XCTAssertEqual(state.metrics.batteryRowValue, "73%")
    }

    func testRefreshBatteryReadingNilKeepsNoBatteryRow() {
        let state = makeState(batteryReader: StubBatteryReader(sample: nil))
        state.metrics.refreshBatteryReading()
        XCTAssertNil(state.metrics.latestBatterySample)
        XCTAssertEqual(state.metrics.batteryRowValue, Strings.batteryNoBattery())
    }

    func testRefreshBatteryReadingNeverClearsAGoodSample() {
        let state = makeState(batteryReader: StubBatteryReader(sample: nil))
        state.metrics.update(with: sample(charge: 64))
        state.metrics.refreshBatteryReading()   // reader returns nil → must not wipe the sample
        XCTAssertEqual(state.metrics.latestBatterySample?.chargePercent, 64)
    }
}
