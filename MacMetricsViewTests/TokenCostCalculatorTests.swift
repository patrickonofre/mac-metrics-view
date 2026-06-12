import XCTest
@testable import MacMetricsView

final class TokenCostCalculatorTests: XCTestCase {

    private func event(
        model: String,
        input: Int = 0,
        output: Int = 0,
        cacheRead: Int = 0,
        cacheCreation: Int = 0,
        reasoning: Int = 0
    ) -> TokenUsageEvent {
        TokenUsageEvent(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
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

    // MARK: - Exact single-event math

    func testSingleOpusEventExactCostIncludingCacheRates() {
        // Opus 4.8: in 5, out 25, cacheRead 0.5, cacheWrite 6.25 USD/MTok.
        let breakdown = TokenCostCalculator.cost(of: [
            event(model: "claude-opus-4-8", input: 1_000_000, output: 200_000, cacheRead: 500_000, cacheCreation: 100_000)
        ])

        // 5 + 0.2×25 + 0.5×0.5 + 0.1×6.25 = 5 + 5 + 0.25 + 0.625
        XCTAssertEqual(breakdown.totalUSD, 10.875, accuracy: 1e-9)
        XCTAssertEqual(breakdown.perModelUSD, [.init(model: "claude-opus-4-8", usd: 10.875)])
        XCTAssertEqual(breakdown.unpricedTokens, 0)
    }

    func testReasoningBillsAtOutputRate() {
        // gpt-5-codex output rate is 10 USD/MTok; reasoning-only event.
        let breakdown = TokenCostCalculator.cost(of: [
            event(model: "gpt-5-codex", reasoning: 2_000_000)
        ])

        XCTAssertEqual(breakdown.totalUSD, 20, accuracy: 1e-9)
    }

    // MARK: - Mixed models / attribution

    func testMixedModelsAttributePerModelAndSumToTotal() {
        let breakdown = TokenCostCalculator.cost(of: [
            event(model: "claude-opus-4-8", input: 1_000_000),   // $5
            event(model: "gpt-5-codex", input: 1_000_000),       // $1.25
            event(model: "claude-opus-4-8", output: 1_000_000)   // $25
        ])

        XCTAssertEqual(breakdown.totalUSD, 31.25, accuracy: 1e-9)
        XCTAssertEqual(breakdown.perModelUSD.map { $0.model }, ["claude-opus-4-8", "gpt-5-codex"])   // largest first
        XCTAssertEqual(breakdown.perModelUSD[0].usd, 30, accuracy: 1e-9)
        XCTAssertEqual(breakdown.perModelUSD[1].usd, 1.25, accuracy: 1e-9)
    }

    // MARK: - Unknown models excluded, surfaced

    func testUnknownModelExcludedFromTotalAndCountedAsUnpriced() {
        let breakdown = TokenCostCalculator.cost(of: [
            event(model: "claude-opus-4-8", input: 1_000_000),                       // $5
            event(model: "mystery-model-9", input: 300, output: 100, cacheRead: 999, reasoning: 50)
        ])

        XCTAssertEqual(breakdown.totalUSD, 5, accuracy: 1e-9)
        XCTAssertEqual(breakdown.perModelUSD.map { $0.model }, ["claude-opus-4-8"])
        // Usage tokens only (input + output + reasoning), matching usageTotal semantics.
        XCTAssertEqual(breakdown.unpricedTokens, 450)
    }

    // MARK: - Degenerate inputs

    func testEmptyEventsYieldZeroBreakdown() {
        XCTAssertEqual(TokenCostCalculator.cost(of: []), .zero)
    }

    func testZeroTokenEventYieldsZeroCostWithoutNegativeOrNaN() {
        let breakdown = TokenCostCalculator.cost(of: [event(model: "claude-opus-4-8")])

        XCTAssertEqual(breakdown.totalUSD, 0)
        XCTAssertFalse(breakdown.totalUSD.isNaN)
        XCTAssertGreaterThanOrEqual(breakdown.totalUSD, 0)
    }

    func testNegativeTokenCountsClampToZero() {
        let breakdown = TokenCostCalculator.cost(of: [
            event(model: "claude-opus-4-8", input: -500, output: -10)
        ])

        XCTAssertEqual(breakdown.totalUSD, 0)
    }

    // MARK: - Combined-provider summation

    func testBreakdownAdditionSumsTotalsAndMergesModels() {
        let claude = TokenCostCalculator.cost(of: [event(model: "claude-opus-4-8", input: 1_000_000)])
        let codex = TokenCostCalculator.cost(of: [
            event(model: "gpt-5-codex", input: 1_000_000),
            event(model: "mystery", input: 100)
        ])

        let combined = claude + codex

        XCTAssertEqual(combined.totalUSD, 6.25, accuracy: 1e-9)
        XCTAssertEqual(combined.perModelUSD.map { $0.model }, ["claude-opus-4-8", "gpt-5-codex"])
        XCTAssertEqual(combined.unpricedTokens, 100)
    }
}
