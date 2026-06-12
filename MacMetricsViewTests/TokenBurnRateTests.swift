import XCTest
@testable import MacMetricsView

final class TokenBurnRateTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func event(
        secondsAgo: TimeInterval,
        model: String = "claude-opus-4-8",
        input: Int = 0,
        output: Int = 0,
        cacheRead: Int = 0,
        cacheCreation: Int = 0,
        reasoning: Int = 0
    ) -> TokenUsageEvent {
        TokenUsageEvent(
            timestamp: now.addingTimeInterval(-secondsAgo),
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

    // MARK: - Exact math

    func testHourOfKnownOpusEventsYieldsExactRateAndProjection() throws {
        // Six Opus events spread across the hour: 600k usage tokens total
        // (500k input + 100k output). Opus 4.8: in $5/MTok, out $25/MTok →
        // cost = 0.5 × 5 + 0.1 × 25 = $5.00 over the window.
        let events = (0..<6).map { index in
            event(secondsAgo: Double(index) * 600, input: 83_000 + index, output: 16_666)
        }
        let totalInput = events.reduce(0) { $0 + $1.inputTokens }     // 498_015
        let totalOutput = events.reduce(0) { $0 + $1.outputTokens }   // 99_996
        let expectedCost = Double(totalInput) * 5 / 1_000_000 + Double(totalOutput) * 25 / 1_000_000

        let breakdown = try XCTUnwrap(TokenBurnRate.compute(events: events, now: now))

        XCTAssertEqual(breakdown.tokensPerHour, Double(totalInput + totalOutput), accuracy: 1e-9)
        XCTAssertEqual(breakdown.costPerHourUSD, expectedCost, accuracy: 1e-9)
        XCTAssertEqual(breakdown.costPerDayUSD, expectedCost * 24, accuracy: 1e-9)
    }

    // MARK: - Window boundaries

    func testEventJustOutsideWindowExcludedAndBoundaryEventsIncluded() throws {
        let events = [
            event(secondsAgo: 3_601, input: 1_000_000),   // excluded
            event(secondsAgo: 3_600, input: 100),          // exactly at the edge: included
            event(secondsAgo: 0, input: 40)                // at now: included
        ]

        let breakdown = try XCTUnwrap(TokenBurnRate.compute(events: events, now: now))

        XCTAssertEqual(breakdown.tokensPerHour, 140, accuracy: 1e-9)
    }

    // MARK: - Nil semantics

    func testEmptyInputReturnsNil() {
        XCTAssertNil(TokenBurnRate.compute(events: [], now: now))
    }

    func testAllEventsOlderThanWindowReturnNil() {
        let events = [
            event(secondsAgo: 3_700, input: 500),
            event(secondsAgo: 80_000, input: 900)
        ]

        XCTAssertNil(TokenBurnRate.compute(events: events, now: now))
    }

    // MARK: - Burst damping

    func testSingleBurstFiveMinutesAgoSpreadsOverFullHourDenominator() throws {
        // 120k usage tokens in one burst → 120k/h, not 120k / 5min = 1.44M/h.
        let breakdown = try XCTUnwrap(TokenBurnRate.compute(
            events: [event(secondsAgo: 300, input: 100_000, output: 20_000)],
            now: now
        ))

        XCTAssertEqual(breakdown.tokensPerHour, 120_000, accuracy: 1e-9)
    }

    // MARK: - Unknown models

    func testUnknownModelEventsAddToTokensPerHourButZeroCost() throws {
        let breakdown = try XCTUnwrap(TokenBurnRate.compute(
            events: [
                event(secondsAgo: 60, model: "mystery-model-9", input: 300, output: 100, reasoning: 50),
                event(secondsAgo: 120, input: 1_000_000)   // Opus: $5
            ],
            now: now
        ))

        XCTAssertEqual(breakdown.tokensPerHour, 1_000_450, accuracy: 1e-9)
        XCTAssertEqual(breakdown.costPerHourUSD, 5, accuracy: 1e-9)
        XCTAssertEqual(breakdown.costPerDayUSD, 120, accuracy: 1e-9)
    }

    // MARK: - Degenerate inputs

    func testNegativeTokenCountsClampToZeroAndOutputNeverNegativeOrNaN() throws {
        let breakdown = try XCTUnwrap(TokenBurnRate.compute(
            events: [event(secondsAgo: 60, input: -500, output: -10, reasoning: -3)],
            now: now
        ))

        XCTAssertEqual(breakdown.tokensPerHour, 0)
        XCTAssertEqual(breakdown.costPerHourUSD, 0)
        XCTAssertEqual(breakdown.costPerDayUSD, 0)
        XCTAssertFalse(breakdown.tokensPerHour.isNaN)
        XCTAssertGreaterThanOrEqual(breakdown.tokensPerHour, 0)
        XCTAssertGreaterThanOrEqual(breakdown.costPerHourUSD, 0)
        XCTAssertGreaterThanOrEqual(breakdown.costPerDayUSD, 0)
    }

    func testReasoningTokensCountTowardUsageAndBillAtOutputRate() throws {
        // gpt-5-codex: output $10/MTok; reasoning bills at the output rate (ADR-002).
        let breakdown = try XCTUnwrap(TokenBurnRate.compute(
            events: [event(secondsAgo: 60, model: "gpt-5-codex", reasoning: 1_000_000)],
            now: now
        ))

        XCTAssertEqual(breakdown.tokensPerHour, 1_000_000, accuracy: 1e-9)
        XCTAssertEqual(breakdown.costPerHourUSD, 10, accuracy: 1e-9)
    }

    func testCacheTokensExcludedFromTokensPerHourButPriced() throws {
        // Opus 4.8 cacheRead $0.5/MTok: cache contributes cost but not tokens/h.
        let breakdown = try XCTUnwrap(TokenBurnRate.compute(
            events: [event(secondsAgo: 60, input: 1_000, cacheRead: 1_000_000)],
            now: now
        ))

        XCTAssertEqual(breakdown.tokensPerHour, 1_000, accuracy: 1e-9)
        XCTAssertEqual(breakdown.costPerHourUSD, 0.505, accuracy: 1e-9)
    }
}
