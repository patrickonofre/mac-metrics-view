import XCTest
@testable import MacMetricsView

@MainActor
final class BatterySamplerTests: XCTestCase {
    private final class FakeReader: BatteryReading {
        var sample: BatterySample?
        private(set) var readCount = 0
        init(sample: BatterySample?) { self.sample = sample }
        func readSample() -> BatterySample? {
            readCount += 1
            return sample
        }
    }

    private final class FakeScheduler: BatteryPollScheduler {
        private var action: (@MainActor () -> Void)?
        func schedule(interval: TimeInterval, _ action: @escaping @MainActor () -> Void) { self.action = action }
        func cancel() { action = nil }
        func fire() { action?() }
    }

    private final class RecordingDelegate: BatterySamplerDelegate {
        private(set) var samples: [BatterySample] = []
        func batterySampler(_ sampler: BatterySampler, didProduce sample: BatterySample) {
            samples.append(sample)
        }
    }

    private func sample(charge: Int = 80) -> BatterySample {
        BatterySample(chargePercent: charge, powerSource: .battery, isCharging: false, timeRemaining: 3600, healthCondition: .normal, cycleCount: 10)
    }

    func testStartEmitsImmediateSample() {
        let reader = FakeReader(sample: sample())
        let sampler = BatterySampler(reader: reader, pollScheduler: FakeScheduler())
        let delegate = RecordingDelegate()
        sampler.delegate = delegate

        sampler.start()

        XCTAssertEqual(delegate.samples.count, 1)
        sampler.stop()
    }

    func testPollFireEmitsAnotherSample() {
        let reader = FakeReader(sample: sample())
        let scheduler = FakeScheduler()
        let sampler = BatterySampler(reader: reader, pollScheduler: scheduler)
        let delegate = RecordingDelegate()
        sampler.delegate = delegate

        sampler.start()
        scheduler.fire()

        XCTAssertEqual(delegate.samples.count, 2)
        sampler.stop()
    }

    func testDoubleStartDoesNotDuplicateImmediateEmission() {
        let reader = FakeReader(sample: sample())
        let sampler = BatterySampler(reader: reader, pollScheduler: FakeScheduler())
        let delegate = RecordingDelegate()
        sampler.delegate = delegate

        sampler.start()
        sampler.start()   // guarded: no second immediate collect

        XCTAssertEqual(delegate.samples.count, 1)
        sampler.stop()
    }

    func testNoEmissionWhenReaderReturnsNil() {
        let reader = FakeReader(sample: nil)
        let sampler = BatterySampler(reader: reader, pollScheduler: FakeScheduler())
        let delegate = RecordingDelegate()
        sampler.delegate = delegate

        sampler.start()

        XCTAssertTrue(delegate.samples.isEmpty)
        sampler.stop()
    }

    func testStopHaltsPollEmissions() {
        let reader = FakeReader(sample: sample())
        let scheduler = FakeScheduler()
        let sampler = BatterySampler(reader: reader, pollScheduler: scheduler)
        let delegate = RecordingDelegate()
        sampler.delegate = delegate

        sampler.start()
        sampler.stop()
        scheduler.fire()   // scheduler cancelled → no-op

        XCTAssertEqual(delegate.samples.count, 1)   // only the start-time emission
    }
}
