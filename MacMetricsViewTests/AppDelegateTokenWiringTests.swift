import XCTest
@testable import MacMetricsView

@MainActor
final class AppDelegateTokenWiringTests: XCTestCase {

    private func event(input: Int) -> TokenUsageEvent {
        TokenUsageEvent(
            timestamp: Date(),
            model: "claude-opus-4-8",
            inputTokens: input,
            outputTokens: 0,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            sessionID: "s1.jsonl",
            projectDir: "p1"
        )
    }

    private final class ScriptedReader: TokenUsageReading {
        var batches: [[TokenUsageEvent]]
        private(set) var readCount = 0
        init(batches: [[TokenUsageEvent]]) { self.batches = batches }
        func readNewEvents() -> [TokenUsageEvent] {
            defer { readCount += 1 }
            guard readCount < batches.count else { return [] }
            return batches[readCount]
        }
    }

    private final class FakeScheduler: TokenPollScheduler {
        private var action: (@MainActor () -> Void)?
        func schedule(interval: TimeInterval, _ action: @escaping @MainActor () -> Void) { self.action = action }
        func cancel() { action = nil }
        func fire() { action?() }
    }

    func testDelegateCallbackForwardsEventsIntoState() {
        let appDelegate = AppDelegate()

        appDelegate.tokenUsageSampler(TokenUsageSampler(), didProduce: [event(input: 100)])

        XCTAssertEqual(appDelegate.state.tokenAggregate.input, 100)
    }

    func testForwardedEventsRenderInMenuBarTitleWhenTokensVisible() {
        let appDelegate = AppDelegate()
        appDelegate.state.setTokenVisible(true)   // identifier style defaults to icons → count only

        appDelegate.tokenUsageSampler(TokenUsageSampler(), didProduce: [event(input: 1_500)])

        XCTAssertTrue(appDelegate.state.visibleMenuBarTitles.contains("1.5k"))
    }

    // Integration: a fake reader drives the real sampler, which dispatches through the
    // AppDelegate delegate method into CPUState.
    func testFakeReaderPollFlowsThroughAppDelegateIntoState() {
        let appDelegate = AppDelegate()
        appDelegate.state.setTokenVisible(true)

        let reader = ScriptedReader(batches: [[event(input: 1_200)]])
        let scheduler = FakeScheduler()
        let sampler = TokenUsageSampler(reader: reader, pollScheduler: scheduler)
        sampler.delegate = appDelegate

        sampler.start()
        scheduler.fire()

        XCTAssertEqual(appDelegate.state.tokenAggregate.input, 1_200)
        XCTAssertTrue(appDelegate.state.visibleMenuBarTitles.contains("1.2k"))
    }
}
