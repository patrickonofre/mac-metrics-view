import Foundation

@MainActor
protocol TokenUsageSamplerDelegate: AnyObject {
    func tokenUsageSampler(_ sampler: TokenUsageSampler, didProduce events: [TokenUsageEvent])
}

/// Injectable seam for the token poll tick. The real implementation drives a main
/// run-loop timer; tests inject a fake they fire manually, avoiding real time.
@MainActor
protocol TokenPollScheduler {
    func schedule(interval: TimeInterval, tolerance: TimeInterval, _ action: @escaping @MainActor () -> Void)
    func cancel()
}

@MainActor
final class RunLoopTokenPollScheduler: TokenPollScheduler {
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

/// Polls a `TokenUsageReading` on a repeating timer and forwards each non-empty batch of
/// newly parsed events to its delegate. Mirrors `CPUSampler`/`DiskSampler` but on a slower
/// cadence, since token events are infrequent (ADR-002).
@MainActor
final class TokenUsageSampler {
    private let reader: TokenUsageReading
    private(set) var interval: TimeInterval
    private(set) var tolerance: TimeInterval = 0
    private let pollScheduler: TokenPollScheduler
    private let executor: SamplingExecutor
    private(set) var isRunning = false

    weak var delegate: TokenUsageSamplerDelegate?

    init(
        reader: TokenUsageReading = ClaudeCodeLogReader(),
        interval: TimeInterval = 5,
        pollScheduler: TokenPollScheduler = RunLoopTokenPollScheduler(),
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
        pollScheduler.schedule(interval: interval, tolerance: tolerance) { [weak self] in
            self?.poll()
        }
    }

    func start(interval: TimeInterval, tolerance: TimeInterval = 0) {
        self.interval = interval
        self.tolerance = tolerance
        if isRunning {
            pollScheduler.cancel()
            pollScheduler.schedule(interval: self.interval, tolerance: self.tolerance) { [weak self] in
                self?.poll()
            }
        } else {
            start()
        }
    }

    func stop() {
        pollScheduler.cancel()
        isRunning = false
    }

    /// One read cycle. The log scan/parse runs off the main thread (PERF-01) and the resulting
    /// batch is delivered on the main actor; an empty read never notifies the delegate. The
    /// reader's per-file state is touched only inside the executor's serial queue.
    func poll() {
        executor.run({ [reader] in reader.readNewEvents() }) { [weak self] events in
            guard let self, !events.isEmpty else { return }
            self.delegate?.tokenUsageSampler(self, didProduce: events)
        }
    }
}
