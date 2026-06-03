import Foundation

@MainActor
protocol TokenUsageSamplerDelegate: AnyObject {
    func tokenUsageSampler(_ sampler: TokenUsageSampler, didProduce events: [TokenUsageEvent])
}

/// Injectable seam for the token poll tick. The real implementation drives a main
/// run-loop timer; tests inject a fake they fire manually, avoiding real time.
@MainActor
protocol TokenPollScheduler {
    func schedule(interval: TimeInterval, _ action: @escaping @MainActor () -> Void)
    func cancel()
}

@MainActor
final class RunLoopTokenPollScheduler: TokenPollScheduler {
    private var timer: Timer?

    nonisolated init() {}

    func schedule(interval: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        timer = MainRunLoopTimer.repeating(every: interval, action)
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
    private let interval: TimeInterval
    private let pollScheduler: TokenPollScheduler
    private var isRunning = false

    weak var delegate: TokenUsageSamplerDelegate?

    init(
        reader: TokenUsageReading = ClaudeCodeLogReader(),
        interval: TimeInterval = 5,
        pollScheduler: TokenPollScheduler = RunLoopTokenPollScheduler()
    ) {
        self.reader = reader
        self.interval = interval
        self.pollScheduler = pollScheduler
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        pollScheduler.schedule(interval: interval) { [weak self] in
            self?.poll()
        }
    }

    func stop() {
        pollScheduler.cancel()
        isRunning = false
    }

    /// One read cycle. Exposed for deterministic test driving; an empty read never
    /// notifies the delegate.
    func poll() {
        let events = reader.readNewEvents()
        guard !events.isEmpty else { return }
        delegate?.tokenUsageSampler(self, didProduce: events)
    }
}
