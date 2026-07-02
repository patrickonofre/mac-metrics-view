import Foundation

@MainActor
protocol GPUSamplerDelegate: AnyObject {
    func gpuSampler(_ sampler: GPUSampler, didProduce sample: GPUSample)
}

/// Injectable seam for the GPU tick. Real implementation drives a main run-loop
/// timer; tests inject a fake they fire manually, avoiding real time.
@MainActor
protocol GPUPollScheduler {
    func schedule(interval: TimeInterval, tolerance: TimeInterval, _ action: @escaping @MainActor () -> Void)
    func cancel()
}

@MainActor
final class RunLoopGPUPollScheduler: GPUPollScheduler {
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

/// Polls GPU utilization on a timer. Unlike CPU/network/disk there is no
/// two-snapshot delta — each read is already an instantaneous value, so the
/// first sample is emitted immediately on `start()` (no baseline wait).
@MainActor
final class GPUSampler {
    private let reader: GPUReading
    private(set) var interval: TimeInterval
    private(set) var tolerance: TimeInterval = 0
    private let pollScheduler: GPUPollScheduler
    /// Runs the IORegistry read off the main thread (OPT-03); the sample is delivered on the
    /// main actor. The reader's cached `io_service_t` is therefore touched only on the
    /// executor's serial queue. Tests inject `InlineSamplingExecutor` to stay synchronous.
    private let executor: SamplingExecutor
    private(set) var isRunning = false

    weak var delegate: GPUSamplerDelegate?

    init(
        reader: GPUReading = IOKitGPUReader(),
        interval: TimeInterval = 1,
        pollScheduler: GPUPollScheduler = RunLoopGPUPollScheduler(),
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
        collect() // instantaneous read — populate immediately
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
        isRunning = false
    }

    private func collect() {
        // Read off-main (OPT-03); deliver on the main actor. Re-check `isRunning` in the
        // delivery so a stop() between read and delivery cannot publish a late sample.
        executor.run({ [reader] in reader.readSample() }) { [weak self] sample in
            guard let self, self.isRunning, let sample else { return }
            self.delegate?.gpuSampler(self, didProduce: sample)
        }
    }
}
