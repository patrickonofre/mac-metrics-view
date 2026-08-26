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
    /// Runs the IORegistry read off the main thread (OPT-03); the delta is computed and
    /// `previousSnapshot` is stored on the main actor (main-confined), mirroring the process
    /// sampler. The reader's cached `io_service_t` is touched only on the executor's serial
    /// queue. Tests inject `InlineSamplingExecutor` to stay synchronous.
    private let executor: SamplingExecutor
    private let workGate = CoalescingSamplingGate()
    private var previousSnapshot: DiskCounterSnapshot?
    private(set) var isRunning = false

    weak var delegate: DiskSamplerDelegate?

    init(
        reader: DiskReading = IOKitDiskReader(),
        interval: TimeInterval = 1,
        pollScheduler: DiskPollScheduler = RunLoopDiskPollScheduler(),
        executor: SamplingExecutor = BackgroundSamplingExecutor()
    ) {
        self.reader = reader
        self.interval = interval
        self.pollScheduler = pollScheduler
        self.executor = executor
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        // Baseline read off-main; snapshot stored on the main actor (OPT-03). The `== nil`
        // guard keeps a tick that raced ahead of the baseline from being clobbered.
        workGate.request { [weak self] finish in
            guard let self else {
                finish()
                return
            }
            self.executor.run({ [reader] in reader.readSnapshot() }) { [weak self] snapshot in
                guard let self else {
                    finish()
                    return
                }
                defer { finish() }
                guard self.isRunning, self.previousSnapshot == nil else { return }
                self.previousSnapshot = snapshot
            }
        }
        pollScheduler.schedule(interval: interval, tolerance: tolerance) { [weak self] in
            self?.collect()
        }
    }

    func start(interval: TimeInterval, tolerance: TimeInterval = 0) {
        // Idempotent (OPT-10): a repeat with identical parameters keeps the running timer.
        if isRunning, interval == self.interval, tolerance == self.tolerance { return }
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
        workGate.cancel()
        previousSnapshot = nil
        isRunning = false
    }

    private func collect() {
        // Read off-main; compute the delta and advance `previousSnapshot` on the main actor
        // (OPT-03). Re-check `isRunning` so a stop() between read and delivery cannot publish.
        workGate.request { [weak self] finish in
            guard let self else {
                finish()
                return
            }
            self.executor.run({ [reader] in reader.readSnapshot() }) { [weak self] current in
                guard let self else {
                    finish()
                    return
                }
                defer { finish() }
                guard self.isRunning, let current else { return }
                defer { self.previousSnapshot = current }

                guard let previous = self.previousSnapshot,
                      let sample = DiskSampleCalculator.sample(previous: previous, current: current)
                else {
                    return
                }

                self.delegate?.diskSampler(self, didProduce: sample)
            }
        }
    }
}
