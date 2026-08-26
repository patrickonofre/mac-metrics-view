import Foundation

@MainActor
protocol AmbientLightSamplerDelegate: AnyObject {
    func ambientLightSampler(_ sampler: AmbientLightSampler, didProduce sample: AmbientLightSample)
}

/// Injectable seam for the poll. The real implementation drives a main run-loop timer;
/// tests inject a fake they fire manually, avoiding real time. Mirrors
/// `TemperaturePollScheduler`.
@MainActor
protocol AmbientLightPollScheduler {
    func schedule(interval: TimeInterval, tolerance: TimeInterval, _ action: @escaping @MainActor () -> Void)
    func cancel()
}

@MainActor
final class RunLoopAmbientLightPollScheduler: AmbientLightPollScheduler {
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

/// Polls the ambient-light reader on a modest main run-loop timer and delivers samples
/// to its delegate on the main actor. Unlike temperature there is no event-driven
/// notification, so this is poll-only. The read runs off the main thread (PERF-01); a
/// `nil` read (no sensor) never notifies the delegate. Idempotent `start`/`stop`.
/// Mirrors `TemperatureSampler`.
@MainActor
final class AmbientLightSampler {
    private let reader: AmbientLightReading
    private(set) var pollInterval: TimeInterval
    private(set) var tolerance: TimeInterval = 0
    private let pollScheduler: AmbientLightPollScheduler
    private let executor: SamplingExecutor
    private let workGate = CoalescingSamplingGate()
    private(set) var isRunning = false

    weak var delegate: AmbientLightSamplerDelegate?

    init(
        reader: AmbientLightReading = IOKitAmbientLightReader(),
        pollInterval: TimeInterval = 10,
        pollScheduler: AmbientLightPollScheduler = RunLoopAmbientLightPollScheduler(),
        executor: SamplingExecutor = BackgroundSamplingExecutor()
    ) {
        self.reader = reader
        self.pollInterval = pollInterval
        self.pollScheduler = pollScheduler
        self.executor = executor
    }

    func start() {
        // Idempotent: a repeated start must not duplicate the timer.
        guard !isRunning else { return }
        isRunning = true

        collect()
        pollScheduler.schedule(interval: pollInterval, tolerance: tolerance) { [weak self] in
            self?.collect()
        }
    }

    func start(interval: TimeInterval, tolerance: TimeInterval = 0) {
        // Idempotent (OPT-10): a repeat with identical parameters keeps the running timer.
        if isRunning, interval == self.pollInterval, tolerance == self.tolerance { return }
        self.pollInterval = interval
        self.tolerance = tolerance
        if isRunning {
            pollScheduler.cancel()
            pollScheduler.schedule(interval: pollInterval, tolerance: self.tolerance) { [weak self] in
                self?.collect()
            }
        } else {
            start()
        }
    }

    func stop() {
        pollScheduler.cancel()
        workGate.cancel()
        isRunning = false
    }

    private func collect() {
        // The private-API read runs off the main thread (PERF-01); the sample is
        // delivered on the main actor. A nil read never notifies the delegate.
        workGate.request { [weak self] finish in
            guard let self else {
                finish()
                return
            }
            self.executor.run({ [reader] in reader.readSample() }) { [weak self] sample in
                guard let self else {
                    finish()
                    return
                }
                defer { finish() }
                guard self.isRunning, let sample else { return }
                self.delegate?.ambientLightSampler(self, didProduce: sample)
            }
        }
    }
}
