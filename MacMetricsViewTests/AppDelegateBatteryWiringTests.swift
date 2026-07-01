import XCTest
@testable import MacMetricsView

@MainActor
final class AppDelegateBatteryWiringTests: XCTestCase {
    // AppDelegate builds its CPUState against UserDefaults.standard; clear the battery
    // visibility key so each test starts from the opt-in default.
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "MetricVisibilitySettings.showBattery")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "MetricVisibilitySettings.showBattery")
        super.tearDown()
    }

    private func sample(charge: Int) -> BatterySample {
        BatterySample(chargePercent: charge, powerSource: .battery, isCharging: false, timeRemaining: 3600, healthCondition: .normal, cycleCount: 10)
    }

    func testDelegateCallbackForwardsSampleIntoState() {
        let appDelegate = AppDelegate()
        appDelegate.batterySampler(appDelegate.batterySampler, didProduce: sample(charge: 77))
        XCTAssertEqual(appDelegate.state.metrics.latestBatterySample?.chargePercent, 77)
    }

    func testForwardedSampleRendersInMenuBarTitleWhenVisible() {
        let appDelegate = AppDelegate()
        appDelegate.state.metrics.setBatteryVisible(true)
        appDelegate.batterySampler(appDelegate.batterySampler, didProduce: sample(charge: 64))
        XCTAssertTrue(appDelegate.state.visibleMenuBarTitles.contains("64%"))
    }

    // Integration: a fake reader drives the real sampler, which dispatches through the
    // AppDelegate delegate method into CPUState.
    func testFakeReaderPollFlowsThroughAppDelegateIntoState() {
        let appDelegate = AppDelegate()
        appDelegate.state.metrics.setBatteryVisible(true)

        let reader = FixedBatteryReader(sample: sample(charge: 91))
        let scheduler = ManualBatteryPollScheduler()
        let sampler = BatterySampler(reader: reader, pollScheduler: scheduler)
        sampler.delegate = appDelegate

        sampler.start()
        scheduler.fire()

        XCTAssertEqual(appDelegate.state.metrics.latestBatterySample?.chargePercent, 91)
        XCTAssertTrue(appDelegate.state.visibleMenuBarTitles.contains("91%"))
        sampler.stop()
    }

    private final class FixedBatteryReader: BatteryReading {
        let sample: BatterySample?
        init(sample: BatterySample?) { self.sample = sample }
        func readSample() -> BatterySample? { sample }
    }

    private final class ManualBatteryPollScheduler: BatteryPollScheduler {
        private var action: (@MainActor () -> Void)?
        func schedule(interval: TimeInterval, tolerance: TimeInterval, _ action: @escaping @MainActor () -> Void) { self.action = action }
        func cancel() { action = nil }
        func fire() { action?() }
    }
}
