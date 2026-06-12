import XCTest
@testable import MacMetricsView

final class TokenRateLimitWindowTests: XCTestCase {

    /// 2026-06-12 00:00:00 UTC — a round hour, so hour offsets read literally.
    private let dayStart = Date(timeIntervalSinceReferenceDate: 802_915_200)

    private func date(hours: Double) -> Date {
        dayStart.addingTimeInterval(hours * 3_600)
    }

    private func event(
        atHours hours: Double,
        model: String = "claude-opus-4-8",
        input: Int = 0,
        output: Int = 0,
        cacheRead: Int = 0,
        cacheCreation: Int = 0,
        reasoning: Int = 0
    ) -> TokenUsageEvent {
        TokenUsageEvent(
            timestamp: date(hours: hours),
            model: model,
            inputTokens: input,
            outputTokens: output,
            cacheReadTokens: cacheRead,
            cacheCreationTokens: cacheCreation,
            reasoningTokens: reasoning,
            sessionID: "s1",
            projectDir: "p1"
        )
    }

    // MARK: - Single block + floor-to-hour

    func testSingleEventOpensFlooredBlockWithUsageAndCost() throws {
        // Event at 14:23 → block [14:00, 19:00); now 16:00 sits inside it.
        // Opus 4.8: 1M input = $5, 100k output = $2.50.
        let events = [event(atHours: 14 + 23.0 / 60, input: 1_000_000, output: 100_000)]

        let block = try XCTUnwrap(TokenRateLimitWindow.activeBlock(events: events, now: date(hours: 16)))

        XCTAssertEqual(block.start, date(hours: 14))
        XCTAssertEqual(block.end, date(hours: 19))
        XCTAssertEqual(block.usage.input, 1_000_000)
        XCTAssertEqual(block.usage.output, 100_000)
        XCTAssertEqual(block.costUSD, 7.5, accuracy: 1e-9)
    }

    // MARK: - Block-end boundary

    func testEventAtExactBlockEndOpensNewBlockAndJustBeforeStays() throws {
        // First event 14:23 → block [14:00, 19:00). An event at exactly 19:00
        // opens [19:00, 24:00); one at 18:59:59 stays in the first block.
        let boundary = [
            event(atHours: 14 + 23.0 / 60, input: 100),
            event(atHours: 19, input: 40)
        ]
        let newBlock = try XCTUnwrap(TokenRateLimitWindow.activeBlock(events: boundary, now: date(hours: 20)))
        XCTAssertEqual(newBlock.start, date(hours: 19))
        XCTAssertEqual(newBlock.end, date(hours: 24))
        XCTAssertEqual(newBlock.usage.input, 40)

        let inside = [
            event(atHours: 14 + 23.0 / 60, input: 100),
            event(atHours: 19 - 1.0 / 3_600, input: 40)   // 18:59:59
        ]
        let sameBlock = try XCTUnwrap(TokenRateLimitWindow.activeBlock(events: inside, now: date(hours: 19 - 0.5 / 3_600)))
        XCTAssertEqual(sameBlock.start, date(hours: 14))
        XCTAssertEqual(sameBlock.usage.input, 140)
    }

    // MARK: - Gap chaining

    func testGapLongerThanFiveHoursOpensNewFlooredBlock() throws {
        // Events 09:10 and 16:45 → blocks [09:00, 14:00) and [16:00, 21:00).
        let events = [
            event(atHours: 9 + 10.0 / 60, input: 100),
            event(atHours: 16 + 45.0 / 60, input: 40)
        ]

        let block = try XCTUnwrap(TokenRateLimitWindow.activeBlock(events: events, now: date(hours: 17)))

        XCTAssertEqual(block.start, date(hours: 16))
        XCTAssertEqual(block.end, date(hours: 21))
        XCTAssertEqual(block.usage.input, 40)

        // The earlier block is also resolvable when `now` falls inside it.
        let earlier = try XCTUnwrap(TokenRateLimitWindow.activeBlock(events: events, now: date(hours: 10)))
        XCTAssertEqual(earlier.start, date(hours: 9))
        XCTAssertEqual(earlier.usage.input, 100)
    }

    // MARK: - Nil semantics

    func testExpiredLastBlockAndEmptyEventsReturnNil() {
        let events = [event(atHours: 9 + 10.0 / 60, input: 100)]   // block [09:00, 14:00)

        XCTAssertNil(TokenRateLimitWindow.activeBlock(events: events, now: date(hours: 14)))   // expired at end
        XCTAssertNil(TokenRateLimitWindow.activeBlock(events: events, now: date(hours: 23)))
        XCTAssertNil(TokenRateLimitWindow.activeBlock(events: [], now: date(hours: 12)))
    }

    // MARK: - Determinism within retention

    func testActiveBlockStableRegardlessOfHowMuchPreGapHistoryIsIncluded() throws {
        // A 24h synthetic day: events every 90 min until 07:30, a >5h gap, then
        // events every 90 min from 14:00. Any ≥5h gap resyncs the chain, so the
        // active block is the same no matter how many pre-gap events are retained.
        let preGap = stride(from: 0.0, through: 7.5, by: 1.5).map { event(atHours: $0, input: 10) }
        let postGap = stride(from: 14.0, through: 22.5, by: 1.5).map { event(atHours: $0, input: 10) }
        let now = date(hours: 22)

        let full = try XCTUnwrap(TokenRateLimitWindow.activeBlock(events: preGap + postGap, now: now))
        let trimmed = try XCTUnwrap(TokenRateLimitWindow.activeBlock(events: Array(preGap.dropFirst(3)) + postGap, now: now))
        let postOnly = try XCTUnwrap(TokenRateLimitWindow.activeBlock(events: postGap, now: now))

        XCTAssertEqual(full, trimmed)
        XCTAssertEqual(full, postOnly)
        XCTAssertEqual(full.start, date(hours: 20))   // [14,19) then the 20:00 event opens [20:00, 25:00)
    }

    // MARK: - now-bounded usage

    func testEventLaterThanNowInsideBlockWindowIsExcludedFromUsage() throws {
        let events = [
            event(atHours: 14, input: 100),
            event(atHours: 16, input: 40)   // inside [14:00, 19:00) but after now
        ]

        let block = try XCTUnwrap(TokenRateLimitWindow.activeBlock(events: events, now: date(hours: 15)))

        XCTAssertEqual(block.usage.input, 100)   // the 16:00 event is excluded
        XCTAssertEqual(block.start, date(hours: 14))
    }

    // MARK: - Degenerate inputs

    func testUnknownModelAddsUsageButZeroCostAndNegativesClamp() throws {
        let events = [
            event(atHours: 14, model: "mystery-model-9", input: 300, output: 100),
            event(atHours: 14.5, input: -500, output: -10, cacheRead: -3, reasoning: -7)
        ]

        let block = try XCTUnwrap(TokenRateLimitWindow.activeBlock(events: events, now: date(hours: 15)))

        XCTAssertEqual(block.usage.input, 300)        // unknown model counted, negatives clamped
        XCTAssertEqual(block.usage.output, 100)
        XCTAssertEqual(block.usage.cacheRead, 0)
        XCTAssertEqual(block.usage.reasoning, 0)
        XCTAssertEqual(block.costUSD, 0)              // unknown model prices to zero
        XCTAssertFalse(block.costUSD.isNaN)
        XCTAssertGreaterThanOrEqual(block.usage.total, 0)
    }

    func testUnsortedInputResolvesSameBlockAsSorted() throws {
        let sorted = [
            event(atHours: 9, input: 10),
            event(atHours: 15, input: 20),
            event(atHours: 16, input: 30)
        ]
        let shuffled = [sorted[2], sorted[0], sorted[1]]

        XCTAssertEqual(
            TokenRateLimitWindow.activeBlock(events: sorted, now: date(hours: 17)),
            try XCTUnwrap(TokenRateLimitWindow.activeBlock(events: shuffled, now: date(hours: 17)))
        )
    }
}
