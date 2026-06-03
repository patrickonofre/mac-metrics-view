import XCTest
@testable import MacMetricsView

final class TokenWindowStatsTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func event(
        at timestamp: Date,
        input: Int = 0,
        output: Int = 0,
        cacheRead: Int = 0,
        cacheCreation: Int = 0,
        session: String = "session-a.jsonl",
        project: String = "project-a"
    ) -> TokenUsageEvent {
        TokenUsageEvent(
            timestamp: timestamp,
            model: "claude-opus-4-8",
            inputTokens: input,
            outputTokens: output,
            cacheReadTokens: cacheRead,
            cacheCreationTokens: cacheCreation,
            sessionID: session,
            projectDir: project
        )
    }

    private func storeWith(_ events: [TokenUsageEvent], resetAt: Date? = nil) -> TokenUsageStore {
        var store = TokenUsageStore(resetAt: resetAt ?? now.addingTimeInterval(-86_400))
        for event in events { store.append(event) }
        return store
    }

    // MARK: - lastHour boundary

    func testLastHourIncludes30MinAgoExcludes90MinAgo() {
        let store = storeWith([
            event(at: now.addingTimeInterval(-30 * 60), input: 5),
            event(at: now.addingTimeInterval(-90 * 60), input: 7)
        ])

        let result = TokenWindowStats.aggregate(store: store, scope: .global, window: .lastHour, now: now)

        XCTAssertEqual(result.input, 5)
    }

    // MARK: - today boundary (local calendar)

    func testTodayExcludesYesterdayIncludesTodayByLocalCalendar() {
        let startOfToday = Calendar.current.startOfDay(for: now)
        let store = storeWith([
            event(at: startOfToday.addingTimeInterval(-60), input: 11),   // yesterday 23:59
            event(at: startOfToday.addingTimeInterval(60), input: 13)     // today 00:01
        ])

        let result = TokenWindowStats.aggregate(store: store, scope: .global, window: .today, now: now)

        XCTAssertEqual(result.input, 13)
    }

    // MARK: - scope

    func testScopeGlobalSessionProjectFilter() {
        // Newest event (MRU) is session s2 / project p2.
        let store = storeWith([
            event(at: now.addingTimeInterval(-300), input: 10, session: "s1", project: "p1"),
            event(at: now.addingTimeInterval(-200), input: 20, session: "s2", project: "p2"),
            event(at: now.addingTimeInterval(-100), input: 40, session: "s2", project: "p2")
        ])

        let global = TokenWindowStats.aggregate(store: store, scope: .global, window: .last24h, now: now)
        let session = TokenWindowStats.aggregate(store: store, scope: .session, window: .last24h, now: now)
        let project = TokenWindowStats.aggregate(store: store, scope: .project, window: .last24h, now: now)

        XCTAssertEqual(global.input, 70)
        XCTAssertEqual(session.input, 60)   // s2 only
        XCTAssertEqual(project.input, 60)   // p2 only
    }

    // MARK: - sinceReset routes to accumulator

    func testSinceResetReturnsAccumulatorNotTimestampFilter() {
        // Reset at now-10s; an old event before reset must not count, a new one must.
        var store = TokenUsageStore(resetAt: now.addingTimeInterval(-10))
        store.append(event(at: now.addingTimeInterval(-3_600), input: 999))  // before reset
        store.append(event(at: now.addingTimeInterval(-5), input: 42))       // after reset

        let result = TokenWindowStats.aggregate(store: store, scope: .global, window: .sinceReset, now: now)

        XCTAssertEqual(result.input, 42)
    }

    // MARK: - aggregate sums every field

    func testAggregateSumsAllTokenKinds() {
        let store = storeWith([
            event(at: now.addingTimeInterval(-10), input: 1, output: 2, cacheRead: 3, cacheCreation: 4),
            event(at: now.addingTimeInterval(-5), input: 10, output: 20, cacheRead: 30, cacheCreation: 40)
        ])

        let result = TokenWindowStats.aggregate(store: store, scope: .global, window: .last24h, now: now)

        XCTAssertEqual(result, TokenAggregate(input: 11, output: 22, cacheRead: 33, cacheCreation: 44))
        XCTAssertEqual(result.total, 110)
    }

    // MARK: - sparkline bucketing

    func testSparklineBucketsSumEventsInSameBucket() {
        // 2 buckets over the lastHour window: [now-60m, now-30m) and [now-30m, now].
        let store = storeWith([
            event(at: now.addingTimeInterval(-50 * 60), input: 5),   // bucket 0
            event(at: now.addingTimeInterval(-40 * 60), input: 7),   // bucket 0
            event(at: now.addingTimeInterval(-10 * 60), input: 9)    // bucket 1
        ])

        let buckets = TokenWindowStats.sparklineBuckets(
            store: store, scope: .global, window: .lastHour, now: now, bucketCount: 2
        )

        XCTAssertEqual(buckets, [12, 9])
    }

    func testSparklineReturnsZeroBucketsWhenEmpty() {
        let store = storeWith([])

        let buckets = TokenWindowStats.sparklineBuckets(
            store: store, scope: .global, window: .lastHour, now: now, bucketCount: 4
        )

        XCTAssertEqual(buckets, [0, 0, 0, 0])
    }

    // MARK: - integration: scope × window matrix

    func testScopeWindowMatrixOnMixedFixture() {
        let store = storeWith([
            event(at: now.addingTimeInterval(-20 * 60), input: 100, session: "s1", project: "p1"),
            event(at: now.addingTimeInterval(-2 * 3_600), input: 200, session: "s2", project: "p2"),
            event(at: now.addingTimeInterval(-90 * 60), input: 400, session: "s2", project: "p2")
        ])
        // Newest timestamp is the -20min event → MRU session/project is s1/p1.

        let globalLastHour = TokenWindowStats.aggregate(store: store, scope: .global, window: .lastHour, now: now)
        let global24h = TokenWindowStats.aggregate(store: store, scope: .global, window: .last24h, now: now)
        let sessionLastHour = TokenWindowStats.aggregate(store: store, scope: .session, window: .lastHour, now: now)

        XCTAssertEqual(globalLastHour.input, 100)   // only the -20min event is within 1h
        XCTAssertEqual(global24h.input, 700)        // all three within 24h
        XCTAssertEqual(sessionLastHour.input, 100)  // MRU session s1, within 1h
    }
}
