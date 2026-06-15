import Foundation

@MainActor
protocol DiskSamplerDelegate: AnyObject {
    func diskSampler(_ sampler: DiskSampler, didProduce sample: DiskSample)
}

/// Injectable seam for the disk tick. Real implementation drives a main run-loop
/// timer; tests inject a fake they can fire manually, avoiding real time.
@MainActor
protocol DiskPollScheduler {
    func schedule(interval: TimeInterval, tolerance: TimeInterval, _ action: @escaping @MainActor () -> Void)
    func cancel()
}

@MainActor
final class RunLoopDiskPollScheduler: DiskPollScheduler {
    private var timer: Timer?

    nonisolated init() {}

    func schedule(interval: TimeInterval, tolerance: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        timer = MainRunLoopTimer.repeating(every: interval, tolerance: tolerance, action)
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }
}

@MainActor
final class DiskSampler {
    private let reader: DiskReading
    private(set) var interval: TimeInterval
    private(set) var tolerance: TimeInterval = 0
    private let pollScheduler: DiskPollScheduler
    private var previousSnapshot: DiskCounterSnapshot?
    private(set) var isRunning = false

    weak var delegate: DiskSamplerDelegate?

    init(
        reader: DiskReading = IOKitDiskReader(),
        interval: TimeInterval = 1,
        pollScheduler: DiskPollScheduler = RunLoopDiskPollScheduler()
    ) {
        self.reader = reader
        self.interval = interval
        self.pollScheduler = pollScheduler
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        previousSnapshot = reader.readSnapshot()
        pollScheduler.schedule(interval: interval, tolerance: tolerance) { [weak self] in
            self?.collect()
        }
    }

    func start(interval: TimeInterval, tolerance: TimeInterval = 0) {
        self.interval = interval
        self.tolerance = tolerance
        if isRunning {
            pollScheduler.cancel()
            pollScheduler.schedule(interval: self.interval, tolerance: self.tolerance) { [weak self] in
                self?.collect()
            }
        } else {
            start()
        }
    }

    func stop() {
        pollScheduler.cancel()
        previousSnapshot = nil
        isRunning = false
    }

    private func collect() {
        guard let current = reader.readSnapshot() else { return }
        defer { previousSnapshot = current }

        guard let previous = previousSnapshot,
              let sample = DiskSampleCalculator.sample(previous: previous, current: current)
        else {
            return
        }

        delegate?.diskSampler(self, didProduce: sample)
    }
}
