import XCTest
@testable import MacMetricsView

@MainActor
final class TokenUsageSamplerTests: XCTestCase {

    private func event(_ input: Int) -> TokenUsageEvent {
        TokenUsageEvent(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            model: "claude-opus-4-8",
            inputTokens: input,
            outputTokens: 0,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            sessionID: "s.jsonl",
            projectDir: "p"
        )
    }

    private final class ScriptedReader: TokenUsageReading {
        var batches: [[TokenUsageEvent]]
        private(set) var readCount = 0

        init(batches: [[TokenUsageEvent]]) {
            self.batches = batches
        }

        func readNewEvents() -> [TokenUsageEvent] {
            defer { readCount += 1 }
            guard readCount < batches.count else { return [] }
            return batches[readCount]
        }
    }

    private final class SpyDelegate: TokenUsageSamplerDelegate {
        var batches: [[TokenUsageEvent]] = []
        func tokenUsageSampler(_ sampler: TokenUsageSampler, didProduce events: [TokenUsageEvent]) {
            batches.append(events)
        }
    }

    private final class FakeScheduler: TokenPollScheduler {
        private(set) var scheduleCount = 0
        private(set) var cancelCount = 0
        private var action: (@MainActor () -> Void)?

        func schedule(interval: TimeInterval, _ action: @escaping @MainActor () -> Void) {
            scheduleCount += 1
            self.action = action
        }

        func cancel() {
            cancelCount += 1
            action = nil
        }

        func fire() { action?() }
    }

    private func makeSampler(
        reader: TokenUsageReading,
        scheduler: FakeScheduler
    ) -> (TokenUsageSampler, SpyDelegate) {
        let delegate = SpyDelegate()
        let sampler = TokenUsageSampler(reader: reader, interval: 5, pollScheduler: scheduler)
        sampler.delegate = delegate
        return (sampler, delegate)
    }

    func testSinglePollWithTwoEventsNotifiesOnce() {
        let reader = ScriptedReader(batches: [[event(1), event(2)]])
        let scheduler = FakeScheduler()
        let (sampler, delegate) = makeSampler(reader: reader, scheduler: scheduler)

        sampler.start()
        scheduler.fire()

        XCTAssertEqual(scheduler.scheduleCount, 1)
        XCTAssertEqual(delegate.batches.count, 1)
        XCTAssertEqual(delegate.batches.first?.map(\.inputTokens), [1, 2])
    }

    func testEmptyReadDoesNotNotify() {
        let reader = ScriptedReader(batches: [[]])
        let scheduler = FakeScheduler()
        let (sampler, delegate) = makeSampler(reader: reader, scheduler: scheduler)

        sampler.start()
        scheduler.fire()

        XCTAssertTrue(delegate.batches.isEmpty)
    }

    func testStopCancelsSchedulerSoNoFurtherPolls() {
        let reader = ScriptedReader(batches: [[event(1)], [event(2)]])
        let scheduler = FakeScheduler()
        let (sampler, delegate) = makeSampler(reader: reader, scheduler: scheduler)

        sampler.start()
        sampler.stop()
        scheduler.fire()

        XCTAssertEqual(scheduler.cancelCount, 1)
        XCTAssertTrue(delegate.batches.isEmpty)
    }

    func testStartIsIdempotent() {
        let reader = ScriptedReader(batches: [[event(1)]])
        let scheduler = FakeScheduler()
        let (sampler, _) = makeSampler(reader: reader, scheduler: scheduler)

        sampler.start()
        sampler.start()

        XCTAssertEqual(scheduler.scheduleCount, 1)
    }

    // MARK: - Integration

    func testScriptedPollsDeliverCumulativeSequence() {
        let reader = ScriptedReader(batches: [
            [event(1), event(2)],
            [],               // suppressed
            [event(3)]
        ])
        let scheduler = FakeScheduler()
        let (sampler, delegate) = makeSampler(reader: reader, scheduler: scheduler)

        sampler.start()
        scheduler.fire()   // batch 0
        scheduler.fire()   // batch 1 (empty, suppressed)
        scheduler.fire()   // batch 2

        XCTAssertEqual(delegate.batches.count, 2)
        XCTAssertEqual(delegate.batches.map { $0.map(\.inputTokens) }, [[1, 2], [3]])
    }
}
