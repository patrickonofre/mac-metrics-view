import XCTest
@testable import MacMetricsView

final class TokenUsageStoreTests: XCTestCase {

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func event(
        at offset: TimeInterval,
        from base: Date? = nil,
        input: Int = 0,
        output: Int = 0,
        cacheRead: Int = 0,
        cacheCreation: Int = 0,
        session: String = "session-a.jsonl",
        project: String = "project-a"
    ) -> TokenUsageEvent {
        TokenUsageEvent(
            timestamp: (base ?? epoch).addingTimeInterval(offset),
            model: "claude-opus-4-8",
            inputTokens: input,
            outputTokens: output,
            cacheReadTokens: cacheRead,
            cacheCreationTokens: cacheCreation,
            sessionID: session,
            projectDir: project
        )
    }

    // MARK: - Eviction

    func testAppendEvictsEventOlderThanHorizonRelativeToNewest() {
        var store = TokenUsageStore(resetAt: epoch)
        store.append(event(at: 0, input: 1))                         // newest after next append
        store.append(event(at: -48 * 3600, input: 9))               // 48h older than newest

        XCTAssertEqual(store.events.count, 1)
        XCTAssertEqual(store.events.first?.inputTokens, 1)
    }

    func testAppendRetainsEventsWithinHorizonInTimestampOrder() {
        var store = TokenUsageStore(resetAt: epoch)
        store.append(event(at: -23 * 3600, input: 1))
        store.append(event(at: -1 * 3600, input: 2))
        store.append(event(at: 0, input: 3))

        XCTAssertEqual(store.events.map(\.inputTokens), [1, 2, 3])
    }

    // MARK: - Reset

    func testResetStampsResetAtAndZeroesAccumulators() {
        var store = TokenUsageStore(resetAt: epoch)
        store.append(event(at: 0, input: 5, session: "s", project: "p"))
        XCTAssertEqual(store.sinceResetGlobal.input, 5)

        let resetMoment = epoch.addingTimeInterval(10)
        store.reset(now: resetMoment)

        XCTAssertEqual(store.resetAt, resetMoment)
        XCTAssertEqual(store.sinceResetGlobal, .zero)
        XCTAssertTrue(store.sinceResetByProject.isEmpty)
        XCTAssertTrue(store.sinceResetBySession.isEmpty)
    }

    func testSinceResetGlobalAccumulatesAfterReset() {
        var store = TokenUsageStore(resetAt: epoch)
        store.reset(now: epoch)
        store.append(event(at: 1, input: 100))

        XCTAssertEqual(store.sinceResetGlobal.input, 100)
    }

    func testSinceResetIgnoresEventsBeforeResetMoment() {
        var store = TokenUsageStore(resetAt: epoch)
        store.reset(now: epoch.addingTimeInterval(100))
        store.append(event(at: 50, input: 7))   // before resetAt

        XCTAssertEqual(store.sinceResetGlobal, .zero)
    }

    // MARK: - Per-scope accumulation

    func testSinceResetSumsPartitionByProjectAndSession() {
        var store = TokenUsageStore(resetAt: epoch)
        store.append(event(at: 1, input: 10, session: "s1", project: "p1"))
        store.append(event(at: 2, input: 20, session: "s2", project: "p1"))
        store.append(event(at: 3, input: 40, session: "s3", project: "p2"))

        XCTAssertEqual(store.sinceResetGlobal.input, 70)
        XCTAssertEqual(store.sinceResetByProject["p1"]?.input, 30)
        XCTAssertEqual(store.sinceResetByProject["p2"]?.input, 40)
        XCTAssertEqual(store.sinceResetBySession["s1"]?.input, 10)
        XCTAssertEqual(store.sinceResetBySession["s2"]?.input, 20)
        XCTAssertEqual(store.sinceResetBySession["s3"]?.input, 40)
    }

    func testAccumulatorSurvivesEventEviction() {
        var store = TokenUsageStore(resetAt: epoch)
        store.append(event(at: 0, input: 5))
        store.append(event(at: 48 * 3600, input: 6))   // evicts the first raw event

        XCTAssertEqual(store.events.count, 1)
        XCTAssertEqual(store.sinceResetGlobal.input, 11)   // both still counted in sums
    }

    // MARK: - TokenAggregate helpers

    func testTokenAggregateZeroIsAllZero() {
        XCTAssertEqual(TokenAggregate.zero, TokenAggregate(input: 0, output: 0, cacheRead: 0, cacheCreation: 0))
    }

    func testTokenAggregateAddingFoldsEventCounts() {
        let result = TokenAggregate.zero.adding(
            event(at: 0, input: 1, output: 2, cacheRead: 3, cacheCreation: 4)
        )

        XCTAssertEqual(result, TokenAggregate(input: 1, output: 2, cacheRead: 3, cacheCreation: 4))
    }
}
