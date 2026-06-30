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
    private(set) var isRunning = false

    weak var delegate: GPUSamplerDelegate?

    init(
        reader: GPUReading = IOKitGPUReader(),
        interval: TimeInterval = 1,
        pollScheduler: GPUPollScheduler = RunLoopGPUPollScheduler()
    ) {
        self.reader = reader
        self.interval = interval
        self.pollScheduler = pollScheduler
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
        guard let sample = reader.readSample() else { return }
        delegate?.gpuSampler(self, didProduce: sample)
    }
}
