import XCTest
@testable import MacMetricsView

@MainActor
final class TemperatureSamplerTests: XCTestCase {
    private final class FakeReader: TemperatureReading {
        var state: TemperatureState = .normal
        var celsius: Double?
        func readSample() -> TemperatureSample? {
            TemperatureSample(celsius: celsius, state: state)
        }
    }

    private final class SpyDelegate: TemperatureSamplerDelegate {
        var samples: [TemperatureSample] = []
        func temperatureSampler(_ sampler: TemperatureSampler, didProduce sample: TemperatureSample) {
            samples.append(sample)
        }
    }

    private final class FakeScheduler: TemperaturePollScheduler {
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

    private final class DeferredExecutor: SamplingExecutor {
        private(set) var queuedReadCount = 0
        private var queuedDeliveries: [() -> Void] = []

        func run<T>(_ read: @escaping () -> T, deliver: @escaping @MainActor (T) -> Void) {
            queuedReadCount += 1
            queuedDeliveries.append {
                let value = read()
                MainActor.assumeIsolated { deliver(value) }
            }
        }

        func completeAll() {
            while !queuedDeliveries.isEmpty {
                queuedDeliveries.removeFirst()()
            }
        }

        func completeNext() {
            queuedDeliveries.removeFirst()()
        }
    }

    private func makeSampler(
        reader: FakeReader,
        center: NotificationCenter,
        scheduler: FakeScheduler
    ) -> (TemperatureSampler, SpyDelegate) {
        let delegate = SpyDelegate()
        let sampler = TemperatureSampler(
            reader: reader,
            notificationCenter: center,
            deliveryQueue: nil,
            pollScheduler: scheduler,
            executor: InlineSamplingExecutor()
        )
        sampler.delegate = delegate
        return (sampler, delegate)
    }

    func testEmitsInitialSampleOnStart() {
        let reader = FakeReader()
        let (sampler, delegate) = makeSampler(reader: reader, center: NotificationCenter(), scheduler: FakeScheduler())

        sampler.start()

        XCTAssertEqual(delegate.samples.map(\.state), [.normal])
    }

    func testSamplesAgainOnThermalStateChange() {
        let reader = FakeReader()
        let center = NotificationCenter()
        let (sampler, delegate) = makeSampler(reader: reader, center: center, scheduler: FakeScheduler())

        sampler.start()
        reader.state = .hot
        center.post(name: ProcessInfo.thermalStateDidChangeNotification, object: nil)

        XCTAssertEqual(delegate.samples.map(\.state), [.normal, .hot])
    }

    func testPollTimerReamplesNumericCelsius() {
        let reader = FakeReader()
        reader.celsius = 48
        let scheduler = FakeScheduler()
        let (sampler, delegate) = makeSampler(reader: reader, center: NotificationCenter(), scheduler: scheduler)

        sampler.start()
        reader.celsius = 55
        scheduler.fire()

        XCTAssertEqual(scheduler.scheduleCount, 1)
        XCTAssertEqual(delegate.samples.map(\.celsius), [48, 55])
    }

    func testStopUnsubscribesAndCancelsTimer() {
        let reader = FakeReader()
        let center = NotificationCenter()
        let scheduler = FakeScheduler()
        let (sampler, delegate) = makeSampler(reader: reader, center: center, scheduler: scheduler)

        sampler.start()
        sampler.stop()
        center.post(name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        scheduler.fire()

        XCTAssertEqual(scheduler.cancelCount, 1)
        XCTAssertEqual(delegate.samples.map(\.state), [.normal])
    }

    func testStartIsIdempotent() {
        let reader = FakeReader()
        let center = NotificationCenter()
        let scheduler = FakeScheduler()
        let (sampler, delegate) = makeSampler(reader: reader, center: center, scheduler: scheduler)

        sampler.start()
        sampler.start()
        center.post(name: ProcessInfo.thermalStateDidChangeNotification, object: nil)

        // One schedule, one initial sample + one notification sample (no duplicate observer).
        XCTAssertEqual(scheduler.scheduleCount, 1)
        XCTAssertEqual(delegate.samples.count, 2)
    }

    func testFactoryFallbackProducesNilCelsiusOnNonNumericArch() {
        let reader = ProcessInfoTemperatureReader()
        let sample = reader.readSample()

        XCTAssertNil(sample?.celsius)
        XCTAssertNotNil(sample?.state)
    }

    func testStartWithIntervalChangesIntervalAndReschedulesIfRunning() {
        let reader = FakeReader()
        let center = NotificationCenter()
        let scheduler = FakeScheduler()
        let (sampler, _) = makeSampler(reader: reader, center: center, scheduler: scheduler)

        sampler.start()
        XCTAssertEqual(scheduler.scheduleCount, 1)

        sampler.start(interval: 5)
        XCTAssertEqual(scheduler.cancelCount, 1)
        XCTAssertEqual(scheduler.scheduleCount, 2)
    }

    func testStartWithIntervalWhenNotRunningDoesNotRescheduleTwice() {
        let reader = FakeReader()
        let center = NotificationCenter()
        let scheduler = FakeScheduler()
        let (sampler, _) = makeSampler(reader: reader, center: center, scheduler: scheduler)

        sampler.start(interval: 5)
        XCTAssertEqual(scheduler.scheduleCount, 1)
        XCTAssertEqual(scheduler.cancelCount, 0)
    }

    func testRepeatedSignalsQueueOnlyOnePendingTemperatureRead() {
        let reader = FakeReader()
        let center = NotificationCenter()
        let scheduler = FakeScheduler()
        let executor = DeferredExecutor()
        let delegate = SpyDelegate()
        let sampler = TemperatureSampler(
            reader: reader,
            notificationCenter: center,
            deliveryQueue: nil,
            pollScheduler: scheduler,
            executor: executor
        )
        sampler.delegate = delegate

        sampler.start()
        scheduler.fire()
        scheduler.fire()
        center.post(name: ProcessInfo.thermalStateDidChangeNotification, object: nil)

        XCTAssertEqual(executor.queuedReadCount, 1)

        executor.completeAll()

        XCTAssertEqual(delegate.samples.count, 2)
    }

    func testStopDropsInFlightTemperatureDeliveryAndPendingRefresh() {
        let reader = FakeReader()
        let scheduler = FakeScheduler()
        let executor = DeferredExecutor()
        let delegate = SpyDelegate()
        let sampler = TemperatureSampler(
            reader: reader,
            notificationCenter: NotificationCenter(),
            deliveryQueue: nil,
            pollScheduler: scheduler,
            executor: executor
        )
        sampler.delegate = delegate

        sampler.start()
        scheduler.fire()
        sampler.stop()
        executor.completeNext()

        XCTAssertEqual(executor.queuedReadCount, 1)
        XCTAssertTrue(delegate.samples.isEmpty)
    }
}
