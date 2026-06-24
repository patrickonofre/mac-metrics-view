import XCTest
@testable import MacMetricsView

@MainActor
final class AmbientLightSamplerTests: XCTestCase {
    private final class FakeReader: AmbientLightReading {
        var lux: Double?
        func readSample() -> AmbientLightSample? {
            guard let lux else { return nil }
            return AmbientLightSample(lux: lux)
        }
    }

    private final class SpyDelegate: AmbientLightSamplerDelegate {
        var samples: [AmbientLightSample] = []
        func ambientLightSampler(_ sampler: AmbientLightSampler, didProduce sample: AmbientLightSample) {
            samples.append(sample)
        }
    }

    private final class FakeScheduler: AmbientLightPollScheduler {
        private(set) var scheduleCount = 0
        private(set) var cancelCount = 0
        private var action: (@MainActor () -> Void)?

        func schedule(interval: TimeInterval, tolerance: TimeInterval, _ action: @escaping @MainActor () -> Void) {
            scheduleCount += 1
            self.action = action
        }

        func cancel() {
            cancelCount += 1
            action = nil
        }

        func fire() {
            action?()
        }
    }

    private func makeSampler(reader: FakeReader, scheduler: FakeScheduler) -> (AmbientLightSampler, SpyDelegate) {
        let delegate = SpyDelegate()
        let sampler = AmbientLightSampler(
            reader: reader,
            pollScheduler: scheduler,
            executor: InlineSamplingExecutor()
        )
        sampler.delegate = delegate
        return (sampler, delegate)
    }

    func testEmitsInitialSampleOnStart() {
        let reader = FakeReader(); reader.lux = 261
        let (sampler, delegate) = makeSampler(reader: reader, scheduler: FakeScheduler())

        sampler.start()

        XCTAssertEqual(delegate.samples.map(\.lux), [261])
    }

    func testPollTimerResamples() {
        let reader = FakeReader(); reader.lux = 130
        let scheduler = FakeScheduler()
        let (sampler, delegate) = makeSampler(reader: reader, scheduler: scheduler)

        sampler.start()
        reader.lux = 255
        scheduler.fire()

        XCTAssertEqual(scheduler.scheduleCount, 1)
        XCTAssertEqual(delegate.samples.map(\.lux), [130, 255])
    }

    func testNilReadNeverNotifiesDelegate() {
        let reader = FakeReader(); reader.lux = nil
        let (sampler, delegate) = makeSampler(reader: reader, scheduler: FakeScheduler())

        sampler.start()

        XCTAssertTrue(delegate.samples.isEmpty)
    }

    func testStartIsIdempotent() {
        let reader = FakeReader(); reader.lux = 200
        let scheduler = FakeScheduler()
        let (sampler, delegate) = makeSampler(reader: reader, scheduler: scheduler)

        sampler.start()
        sampler.start()

        XCTAssertEqual(scheduler.scheduleCount, 1)
        XCTAssertEqual(delegate.samples.count, 1)
    }

    func testStopCancelsTimer() {
        let reader = FakeReader(); reader.lux = 200
        let scheduler = FakeScheduler()
        let (sampler, delegate) = makeSampler(reader: reader, scheduler: scheduler)

        sampler.start()
        sampler.stop()
        scheduler.fire()

        XCTAssertEqual(scheduler.cancelCount, 1)
        XCTAssertEqual(delegate.samples.count, 1)
    }

    func testStartWithIntervalReschedulesIfRunning() {
        let reader = FakeReader(); reader.lux = 200
        let scheduler = FakeScheduler()
        let (sampler, _) = makeSampler(reader: reader, scheduler: scheduler)

        sampler.start()
        XCTAssertEqual(scheduler.scheduleCount, 1)

        sampler.start(interval: 5)
        XCTAssertEqual(scheduler.cancelCount, 1)
        XCTAssertEqual(scheduler.scheduleCount, 2)
        XCTAssertEqual(sampler.pollInterval, 5)
    }
}
