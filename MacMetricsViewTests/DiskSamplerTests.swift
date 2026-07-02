import XCTest
@testable import MacMetricsView

@MainActor
final class DiskSamplerTests: XCTestCase {
    private final class ScriptedDiskReader: DiskReading {
        var snapshots: [DiskCounterSnapshot?]
        private(set) var readCount = 0

        init(snapshots: [DiskCounterSnapshot?]) {
            self.snapshots = snapshots
        }

        func readSnapshot() -> DiskCounterSnapshot? {
            defer { readCount += 1 }
            guard readCount < snapshots.count else { return nil }
            return snapshots[readCount]
        }
    }

    private final class SpyDelegate: DiskSamplerDelegate {
        var samples: [DiskSample] = []
        func diskSampler(_ sampler: DiskSampler, didProduce sample: DiskSample) {
            samples.append(sample)
        }
    }

    private final class FakeScheduler: DiskPollScheduler {
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
        reader: DiskReading,
        scheduler: FakeScheduler
    ) -> (DiskSampler, SpyDelegate) {
        let delegate = SpyDelegate()
        let sampler = DiskSampler(reader: reader, interval: 1, pollScheduler: scheduler, executor: InlineSamplingExecutor())
        sampler.delegate = delegate
        return (sampler, delegate)
    }

    func testStartEmitsNoSampleWithOnlyBaselineSnapshot() {
        let reader = ScriptedDiskReader(snapshots: [
            DiskCounterSnapshot(timestamp: Date(timeIntervalSince1970: 0), bytesRead: 1_000, bytesWritten: 2_000)
        ])
        let scheduler = FakeScheduler()
        let (sampler, delegate) = makeSampler(reader: reader, scheduler: scheduler)

        sampler.start()

        XCTAssertEqual(delegate.samples.count, 0)
        XCTAssertEqual(scheduler.scheduleCount, 1)
        XCTAssertEqual(reader.readCount, 1)
    }

    func testTwoSnapshotsAcrossOneTickEmitOneSample() {
        let reader = ScriptedDiskReader(snapshots: [
            DiskCounterSnapshot(timestamp: Date(timeIntervalSince1970: 0), bytesRead: 1_000, bytesWritten: 2_000),
            DiskCounterSnapshot(timestamp: Date(timeIntervalSince1970: 1), bytesRead: 2_024, bytesWritten: 2_256)
        ])
        let scheduler = FakeScheduler()
        let (sampler, delegate) = makeSampler(reader: reader, scheduler: scheduler)

        sampler.start()
        scheduler.fire()

        XCTAssertEqual(delegate.samples.count, 1)
        XCTAssertEqual(delegate.samples.first?.readBytesPerSecond, 1_024)
        XCTAssertEqual(delegate.samples.first?.writeBytesPerSecond, 256)
    }

    func testReaderReturningNilDoesNotEmitOrCrash() {
        let reader = ScriptedDiskReader(snapshots: [nil, nil, nil])
        let scheduler = FakeScheduler()
        let (sampler, delegate) = makeSampler(reader: reader, scheduler: scheduler)

        sampler.start()
        scheduler.fire()
        scheduler.fire()

        XCTAssertEqual(delegate.samples.count, 0)
    }

    func testStopCancelsSchedulerAndClearsBaseline() {
        let reader = ScriptedDiskReader(snapshots: [
            DiskCounterSnapshot(timestamp: Date(timeIntervalSince1970: 0), bytesRead: 1_000, bytesWritten: 2_000),
            DiskCounterSnapshot(timestamp: Date(timeIntervalSince1970: 1), bytesRead: 2_024, bytesWritten: 2_256)
        ])
        let scheduler = FakeScheduler()
        let (sampler, delegate) = makeSampler(reader: reader, scheduler: scheduler)

        sampler.start()
        sampler.stop()
        scheduler.fire()

        XCTAssertEqual(scheduler.cancelCount, 1)
        XCTAssertEqual(delegate.samples.count, 0)
    }

    func testStartIsIdempotent() {
        let reader = ScriptedDiskReader(snapshots: [
            DiskCounterSnapshot(timestamp: Date(timeIntervalSince1970: 0), bytesRead: 1_000, bytesWritten: 2_000),
            DiskCounterSnapshot(timestamp: Date(timeIntervalSince1970: 1), bytesRead: 2_024, bytesWritten: 2_256)
        ])
        let scheduler = FakeScheduler()
        let (sampler, _) = makeSampler(reader: reader, scheduler: scheduler)

        sampler.start()
        sampler.start()

        XCTAssertEqual(scheduler.scheduleCount, 1)
    }

    func testStartWithIntervalChangesIntervalAndReschedulesIfRunning() {
        let reader = ScriptedDiskReader(snapshots: [
            DiskCounterSnapshot(timestamp: Date(timeIntervalSince1970: 0), bytesRead: 1_000, bytesWritten: 2_000),
            DiskCounterSnapshot(timestamp: Date(timeIntervalSince1970: 1), bytesRead: 2_024, bytesWritten: 2_256)
        ])
        let scheduler = FakeScheduler()
        let (sampler, _) = makeSampler(reader: reader, scheduler: scheduler)

        sampler.start()
        XCTAssertEqual(scheduler.scheduleCount, 1)

        sampler.start(interval: 3)
        XCTAssertEqual(scheduler.cancelCount, 1)
        XCTAssertEqual(scheduler.scheduleCount, 2)
    }

    func testStartWithIntervalWhenNotRunningDoesNotRescheduleTwice() {
        let reader = ScriptedDiskReader(snapshots: [])
        let scheduler = FakeScheduler()
        let (sampler, _) = makeSampler(reader: reader, scheduler: scheduler)

        sampler.start(interval: 3)
        XCTAssertEqual(scheduler.scheduleCount, 1)
        XCTAssertEqual(scheduler.cancelCount, 0)
    }
}
