import XCTest
@testable import MacMetricsView

@MainActor
final class GPUSamplerTests: XCTestCase {
    private final class ScriptedGPUReader: GPUReading {
        var samples: [GPUSample?]
        private(set) var readCount = 0

        init(samples: [GPUSample?]) {
            self.samples = samples
        }

        func readSample() -> GPUSample? {
            defer { readCount += 1 }
            guard readCount < samples.count else { return nil }
            return samples[readCount]
        }
    }

    private final class SpyDelegate: GPUSamplerDelegate {
        var samples: [GPUSample] = []
        func gpuSampler(_ sampler: GPUSampler, didProduce sample: GPUSample) {
            samples.append(sample)
        }
    }

    private final class FakeScheduler: GPUPollScheduler {
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

    private func makeSampler(
        reader: GPUReading,
        scheduler: FakeScheduler
    ) -> (GPUSampler, SpyDelegate) {
        let delegate = SpyDelegate()
        let sampler = GPUSampler(reader: reader, interval: 1, pollScheduler: scheduler)
        sampler.delegate = delegate
        return (sampler, delegate)
    }

    func testStartEmitsImmediateSample() {
        let reader = ScriptedGPUReader(samples: [GPUSample(utilizationPercent: 42)])
        let scheduler = FakeScheduler()
        let (sampler, delegate) = makeSampler(reader: reader, scheduler: scheduler)

        sampler.start()

        XCTAssertEqual(delegate.samples.map(\.utilizationPercent), [42])
        XCTAssertEqual(scheduler.scheduleCount, 1)
        XCTAssertEqual(reader.readCount, 1)
    }

    func testTickAfterStartEmitsNextSample() {
        let reader = ScriptedGPUReader(samples: [GPUSample(utilizationPercent: 42), GPUSample(utilizationPercent: 77)])
        let scheduler = FakeScheduler()
        let (sampler, delegate) = makeSampler(reader: reader, scheduler: scheduler)

        sampler.start()
        scheduler.fire()

        XCTAssertEqual(delegate.samples.map(\.utilizationPercent), [42, 77])
    }

    func testNilReadDoesNotEmitOrCrash() {
        let reader = ScriptedGPUReader(samples: [nil, nil])
        let scheduler = FakeScheduler()
        let (sampler, delegate) = makeSampler(reader: reader, scheduler: scheduler)

        sampler.start()
        scheduler.fire()

        XCTAssertEqual(delegate.samples.count, 0)
    }

    func testStopCancelsAndPreventsFurtherSamples() {
        let reader = ScriptedGPUReader(samples: [GPUSample(utilizationPercent: 42), GPUSample(utilizationPercent: 77)])
        let scheduler = FakeScheduler()
        let (sampler, delegate) = makeSampler(reader: reader, scheduler: scheduler)

        sampler.start()
        sampler.stop()
        scheduler.fire()

        XCTAssertEqual(scheduler.cancelCount, 1)
        XCTAssertEqual(delegate.samples.map(\.utilizationPercent), [42]) // only the start sample
        XCTAssertFalse(sampler.isRunning)
    }

    func testStartIsIdempotent() {
        let reader = ScriptedGPUReader(samples: [GPUSample(utilizationPercent: 42), GPUSample(utilizationPercent: 77)])
        let scheduler = FakeScheduler()
        let (sampler, delegate) = makeSampler(reader: reader, scheduler: scheduler)

        sampler.start()
        sampler.start()

        XCTAssertEqual(scheduler.scheduleCount, 1)
        XCTAssertEqual(delegate.samples.count, 1)
    }

    func testStartWithIntervalChangesIntervalAndReschedulesIfRunning() {
        let reader = ScriptedGPUReader(samples: [GPUSample(utilizationPercent: 42), GPUSample(utilizationPercent: 77)])
        let scheduler = FakeScheduler()
        let (sampler, _) = makeSampler(reader: reader, scheduler: scheduler)

        sampler.start()
        sampler.start(interval: 3)

        XCTAssertEqual(scheduler.cancelCount, 1)
        XCTAssertEqual(scheduler.scheduleCount, 2)
        XCTAssertEqual(sampler.interval, 3)
    }

    func testStartWithIntervalWhenNotRunningStartsOnce() {
        let reader = ScriptedGPUReader(samples: [GPUSample(utilizationPercent: 42)])
        let scheduler = FakeScheduler()
        let (sampler, _) = makeSampler(reader: reader, scheduler: scheduler)

        sampler.start(interval: 3)

        XCTAssertEqual(scheduler.scheduleCount, 1)
        XCTAssertEqual(scheduler.cancelCount, 0)
    }
}
