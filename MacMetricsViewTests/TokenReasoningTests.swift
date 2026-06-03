import XCTest
@testable import MacMetricsView

/// Covers the shared `reasoning` category added to `TokenUsageEvent`/`TokenAggregate`
/// (task_02, ADR-002/004): it folds into the totals and windowed aggregation, while
/// Claude-shaped events (reasoning = 0) stay bit-for-bit unchanged.
final class TokenReasoningTests: XCTestCase {

    private func event(
        at date: Date = Date(timeIntervalSince1970: 1_000),
        input: Int = 0,
        output: Int = 0,
        cacheRead: Int = 0,
        cacheCreation: Int = 0,
        reasoning: Int = 0,
        session: String = "s1.jsonl",
        project: String = "p1"
    ) -> TokenUsageEvent {
        TokenUsageEvent(
            timestamp: date,
            model: "gpt-5-codex",
            inputTokens: input,
            outputTokens: output,
            cacheReadTokens: cacheRead,
            cacheCreationTokens: cacheCreation,
            reasoningTokens: reasoning,
            sessionID: session,
            projectDir: project
        )
    }

    // MARK: - Folding into the aggregate

    func testAddingEventRaisesReasoning() {
        let aggregate = TokenAggregate.zero.adding(event(reasoning: 50))

        XCTAssertEqual(aggregate.reasoning, 50)
    }

    func testTotalIncludesReasoning() {
        let aggregate = TokenAggregate(input: 10, output: 20, cacheRead: 5, cacheCreation: 3, reasoning: 7)

        XCTAssertEqual(aggregate.total, 45)         // 10 + 20 + 5 + 3 + 7
    }

    func testUsageTotalIncludesReasoningButExcludesCache() {
        let aggregate = TokenAggregate(input: 10, output: 20, cacheRead: 5, cacheCreation: 3, reasoning: 7)

        XCTAssertEqual(aggregate.usageTotal, 37)    // 10 + 20 + 7, cache excluded
    }

    func testZeroHasZeroReasoning() {
        XCTAssertEqual(TokenAggregate.zero.reasoning, 0)
    }

    // MARK: - Claude regression (reasoning = 0)

    func testClaudeShapedBatchUnchanged() {
        // A Claude-shaped batch never sets reasoning; totals must match the pre-reasoning math.
        let claude = TokenAggregate.zero
            .adding(event(input: 100, output: 200, cacheRead: 300, cacheCreation: 400))
            .adding(event(input: 1, output: 2, cacheRead: 3, cacheCreation: 4))

        XCTAssertEqual(claude.reasoning, 0)
        XCTAssertEqual(claude.total, 100 + 200 + 300 + 400 + 1 + 2 + 3 + 4)
        XCTAssertEqual(claude.usageTotal, 100 + 200 + 1 + 2)   // input + output only
    }

    // MARK: - Windowed aggregation

    func testWindowStatsSumsReasoningIntoAggregate() {
        let store = TokenUsageStore(
            resetAt: Date(timeIntervalSince1970: 0),
            events: [
                event(at: Date(), input: 100, output: 200, reasoning: 80),
                event(at: Date(), input: 10, output: 20, reasoning: 5)
            ]
        )

        let aggregate = TokenWindowStats.aggregate(store: store, scope: .global, window: .last24h, now: Date())

        XCTAssertEqual(aggregate.reasoning, 85)
        XCTAssertEqual(aggregate.usageTotal, 100 + 200 + 10 + 20 + 85)
    }

    func testWindowStatsReasoningZeroBatchUnchanged() {
        let store = TokenUsageStore(
            resetAt: Date(timeIntervalSince1970: 0),
            events: [event(at: Date(), input: 100, output: 200)]
        )

        let aggregate = TokenWindowStats.aggregate(store: store, scope: .global, window: .last24h, now: Date())

        XCTAssertEqual(aggregate.reasoning, 0)
        XCTAssertEqual(aggregate.usageTotal, 300)
    }
}
