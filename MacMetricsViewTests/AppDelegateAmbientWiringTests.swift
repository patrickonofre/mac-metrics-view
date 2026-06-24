import XCTest
@testable import MacMetricsView

@MainActor
final class AppDelegateAmbientWiringTests: XCTestCase {
    // AppDelegate builds CPUState against UserDefaults.standard; clear the ambient keys so
    // each test starts from the opt-in default (feature off). With the feature off,
    // CPUState.update(with:) never reads the system appearance, so no NSApp is required.
    private let ambientKeys = [
        "AmbientThemeSettings.isEnabled",
        "AmbientThemeSettings.lowLux",
        "AmbientThemeSettings.highLux",
        "AmbientThemeSettings.dwellSeconds"
    ]

    override func setUp() {
        super.setUp()
        ambientKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    override func tearDown() {
        ambientKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        super.tearDown()
    }

    func testDelegateCallbackForwardsSampleIntoState() {
        let appDelegate = AppDelegate()
        appDelegate.ambientLightSampler(appDelegate.ambientLightSampler, didProduce: AmbientLightSample(lux: 200))
        XCTAssertEqual(appDelegate.state.latestAmbientSample?.lux, 200)
    }

    func testFakeReaderPollFlowsThroughAppDelegateIntoState() {
        let appDelegate = AppDelegate()

        let reader = FixedAmbientReader(lux: 312)
        let scheduler = ManualAmbientPollScheduler()
        let sampler = AmbientLightSampler(reader: reader, pollScheduler: scheduler, executor: InlineSamplingExecutor())
        sampler.delegate = appDelegate

        sampler.start()
        scheduler.fire()

        XCTAssertEqual(appDelegate.state.latestAmbientSample?.lux, 312)
        sampler.stop()
    }

    func testSamplerStaysStoppedWhenDisabled() {
        let appDelegate = AppDelegate()
        appDelegate.reevaluateAmbientSampler()
        XCTAssertFalse(appDelegate.ambientLightSampler.isRunning)
    }

    func testSamplerStartsWhenEnabled() {
        let appDelegate = AppDelegate()
        appDelegate.state.setAmbientThemeSettings(
            AmbientThemeSettings(isEnabled: true, lowLux: 175, highLux: 240, dwellSeconds: 20)
        )
        appDelegate.reevaluateAmbientSampler()

        XCTAssertTrue(appDelegate.ambientLightSampler.isRunning)
        appDelegate.ambientLightSampler.stop()
    }

    private final class FixedAmbientReader: AmbientLightReading {
        let lux: Double
        init(lux: Double) { self.lux = lux }
        func readSample() -> AmbientLightSample? { AmbientLightSample(lux: lux) }
    }

    private final class ManualAmbientPollScheduler: AmbientLightPollScheduler {
        private var action: (@MainActor () -> Void)?
        func schedule(interval: TimeInterval, tolerance: TimeInterval, _ action: @escaping @MainActor () -> Void) { self.action = action }
        func cancel() { action = nil }
        func fire() { action?() }
    }
}
