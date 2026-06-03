import XCTest
@testable import MacMetricsView

@MainActor
final class AppDelegateTokenWiringTests: XCTestCase {

    private func event(input: Int, model: String = "claude-opus-4-8") -> TokenUsageEvent {
        TokenUsageEvent(
            timestamp: Date(),
            model: model,
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

    // MARK: - Provider-tagged routing (task_07)

    func testCodexSamplerBatchRoutesToCodexStore() {
        let appDelegate = AppDelegate()

        appDelegate.tokenUsageSampler(appDelegate.codexTokenSampler, didProduce: [event(input: 70, model: "gpt-5-codex")])

        XCTAssertEqual(appDelegate.state.tokenStores[.codex]?.events.count, 1)
        XCTAssertEqual(appDelegate.state.tokenStores[.claude]?.events.count, 0)
    }

    func testClaudeSamplerBatchRoutesToClaudeStore() {
        let appDelegate = AppDelegate()

        appDelegate.tokenUsageSampler(appDelegate.tokenSampler, didProduce: [event(input: 100)])

        XCTAssertEqual(appDelegate.state.tokenStores[.claude]?.events.count, 1)
        XCTAssertEqual(appDelegate.state.tokenStores[.codex]?.events.count, 0)
    }

    func testBothBatchesReachTheirStoresAndCombinedReflectsBoth() {
        let appDelegate = AppDelegate()   // default selection: combined

        appDelegate.tokenUsageSampler(appDelegate.tokenSampler, didProduce: [event(input: 100)])
        appDelegate.tokenUsageSampler(appDelegate.codexTokenSampler, didProduce: [event(input: 40, model: "gpt-5-codex")])

        XCTAssertEqual(appDelegate.state.tokenAggregate.input, 140)   // combined sum

        // Switching provider re-renders from the already-ingested batches, no restart.
        appDelegate.state.setTokenProvider(.codex)
        XCTAssertEqual(appDelegate.state.tokenAggregate.input, 40)
        appDelegate.state.setTokenProvider(.claude)
        XCTAssertEqual(appDelegate.state.tokenAggregate.input, 100)
    }
}
