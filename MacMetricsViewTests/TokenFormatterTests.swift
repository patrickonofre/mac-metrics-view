import XCTest
@testable import MacMetricsView

final class TokenFormatterTests: XCTestCase {

    private func aggregate(
        input: Int = 0,
        output: Int = 0,
        cacheRead: Int = 0,
        cacheCreation: Int = 0,
        reasoning: Int = 0
    ) -> TokenAggregate {
        TokenAggregate(input: input, output: output, cacheRead: cacheRead, cacheCreation: cacheCreation, reasoning: reasoning)
    }

    // MARK: - Humanization

    func testHumanizedCompactsThousandsAndMillions() {
        XCTAssertEqual(TokenFormatter.humanized(950), "950")
        XCTAssertEqual(TokenFormatter.humanized(1_500), "1.5k")
        XCTAssertEqual(TokenFormatter.humanized(2_300_000), "2.3M")
    }

    func testHumanizedClampsNegativeToZero() {
        XCTAssertEqual(TokenFormatter.humanized(-5), "0")
    }

    // MARK: - Menu bar title

    func testMenuBarTitleWithAndWithoutLabel() {
        let today = aggregate(input: 1_500)   // total 1500

        XCTAssertEqual(TokenFormatter.menuBarTitle(for: today, showLabel: true), "TOK 1.5k")
        XCTAssertEqual(TokenFormatter.menuBarTitle(for: today, showLabel: false), "1.5k")
    }

    func testMenuBarTitleForAbsentDataIsPlaceholderNotZero() {
        XCTAssertEqual(TokenFormatter.menuBarTitle(for: nil, showLabel: false), "--")
    }

    func testMenuBarTitleExcludesCacheFromTotal() {
        let agg = aggregate(input: 1_000, output: 2_000, cacheRead: 5_000, cacheCreation: 5_000)

        // Headline = input + output (3k), not the 13k full sum.
        XCTAssertEqual(TokenFormatter.menuBarTitle(for: agg, showLabel: false), "3.0k")
    }

    // MARK: - Breakdown

    func testBreakdownRendersInputOutputCache() {
        let agg = aggregate(input: 1_000, output: 2_000, cacheRead: 1_500, cacheCreation: 1_500)

        let rows = TokenFormatter.breakdown(for: agg, language: .english)

        XCTAssertEqual(rows.map(\.label), ["Input", "Output", "Cache"])
        XCTAssertEqual(rows.map(\.value), ["1.0k", "2.0k", "3.0k"])   // cache = read + creation
    }

    func testBreakdownAppendsReasoningRowOnlyWhenPresent() {
        // Codex shape: reasoning > 0 → four rows in input/output/reasoning/cache order.
        let codex = aggregate(input: 1_000, output: 2_000, cacheRead: 500, reasoning: 120)
        let rows = TokenFormatter.breakdown(for: codex, language: .english)
        XCTAssertEqual(rows.map(\.label), ["Input", "Output", "Reasoning", "Cache"])
        XCTAssertEqual(rows.map(\.value), ["1.0k", "2.0k", "120", "500"])

        // Claude shape: reasoning == 0 → unchanged three rows, no reasoning row.
        let claude = aggregate(input: 1_000, output: 2_000, cacheRead: 500)
        XCTAssertEqual(TokenFormatter.breakdown(for: claude, language: .english).map(\.label),
                       ["Input", "Output", "Cache"])
    }

    // MARK: - Provider-aware menu bar label

    func testProviderAwareMenuBarLabelDiffersPerSelection() {
        let claude = TokenFormatter.menuBarLabel(for: .claude, language: .english)
        let codex = TokenFormatter.menuBarLabel(for: .codex, language: .english)
        let gemini = TokenFormatter.menuBarLabel(for: .gemini, language: .english)
        let combined = TokenFormatter.menuBarLabel(for: .combined, language: .english)

        XCTAssertEqual(claude, Strings.tokenProviderClaude(.english))
        XCTAssertEqual(codex, Strings.tokenProviderCodex(.english))
        XCTAssertEqual(gemini, Strings.tokenProviderGemini(.english))
        XCTAssertEqual(combined, Strings.tokenProviderCombined(.english))
        XCTAssertNotEqual(claude, codex)
        XCTAssertNotEqual(codex, gemini)
        XCTAssertNotEqual(gemini, combined)
    }

    // MARK: - Empty state

    func testEmptyStateDetectionAndCopy() {
        XCTAssertTrue(TokenFormatter.isEmpty(nil))
        XCTAssertTrue(TokenFormatter.isEmpty(.zero))
        XCTAssertFalse(TokenFormatter.isEmpty(aggregate(input: 1)))

        let empty = TokenFormatter.emptyState(.english)
        XCTAssertFalse(empty.isEmpty)
        XCTAssertNotEqual(empty, "0")
        XCTAssertEqual(empty, Strings.tokenEmptyState(.english))
    }

    // MARK: - Severity

    func testSeverityIsAlwaysNormal() {
        XCTAssertEqual(TokenFormatter.menuBarTextStyle(for: nil), .normal)
        XCTAssertEqual(TokenFormatter.menuBarTextStyle(for: aggregate(input: 9_999_999)), .normal)
    }

    // MARK: - Model display name

    func testModelDisplayNameKnownFamilies() {
        XCTAssertEqual(TokenFormatter.modelDisplayName("claude-opus-4-8"), "Opus 4.8")
        XCTAssertEqual(TokenFormatter.modelDisplayName("claude-sonnet-4-6"), "Sonnet 4.6")
        XCTAssertEqual(TokenFormatter.modelDisplayName("claude-haiku-4-5-20251001"), "Haiku 4.5")
        // Legacy form: version digits precede the family, date suffix ignored.
        XCTAssertEqual(TokenFormatter.modelDisplayName("claude-3-5-sonnet-20241022"), "Sonnet 3.5")
    }

    func testModelDisplayNameEmptyAndSynthetic() {
        XCTAssertNil(TokenFormatter.modelDisplayName(""))
        XCTAssertNil(TokenFormatter.modelDisplayName("   "))
        XCTAssertNil(TokenFormatter.modelDisplayName("<synthetic>"))
    }

    func testModelDisplayNameOpenAIFamilies() {
        XCTAssertEqual(TokenFormatter.modelDisplayName("gpt-5-codex"), "GPT-5 Codex")
        XCTAssertEqual(TokenFormatter.modelDisplayName("gpt-5.3-codex"), "GPT-5.3 Codex")
        XCTAssertEqual(TokenFormatter.modelDisplayName("gpt-5.5"), "GPT-5.5")
        XCTAssertEqual(TokenFormatter.modelDisplayName("gpt-4o"), "GPT-4o")
        XCTAssertEqual(TokenFormatter.modelDisplayName("o3"), "o3")
        XCTAssertEqual(TokenFormatter.modelDisplayName("o4-mini"), "o4 Mini")
        // Claude families are unaffected by the OpenAI branch.
        XCTAssertEqual(TokenFormatter.modelDisplayName("claude-opus-4-8"), "Opus 4.8")
    }

    func testModelDisplayNameUnknownFallsBackToStrippedId() {
        XCTAssertEqual(TokenFormatter.modelDisplayName("claude-future-9-0"), "future-9-0")
        // A genuinely unknown vendor still falls back to the raw id, never blank.
        XCTAssertEqual(TokenFormatter.modelDisplayName("mistral-large-2"), "mistral-large-2")
    }
}

// MARK: - Cost formatting (Phase 1)

extension TokenFormatterTests {
    func testCostStringZeroRendersAsZeroDollars() {
        XCTAssertEqual(TokenFormatter.costString(0), "$0.00")
    }

    func testCostStringSubCentBoundary() {
        XCTAssertEqual(TokenFormatter.costString(0.009), "< $0.01")
        XCTAssertEqual(TokenFormatter.costString(0.0001), "< $0.01")
        XCTAssertEqual(TokenFormatter.costString(0.01), "$0.01")
    }

    func testCostStringTwoDecimalsBelowTen() {
        XCTAssertEqual(TokenFormatter.costString(0.044), "$0.04")
        XCTAssertEqual(TokenFormatter.costString(1.234), "$1.23")
        XCTAssertEqual(TokenFormatter.costString(9.999), "$10.00")   // %.2f rounding at the edge
    }

    func testCostStringOneDecimalBetweenTenAndHundred() {
        XCTAssertEqual(TokenFormatter.costString(12.44), "$12.4")
        XCTAssertEqual(TokenFormatter.costString(10), "$10.0")
        XCTAssertEqual(TokenFormatter.costString(99.94), "$99.9")
    }

    func testCostStringWholeDollarsAtHundredAndAbove() {
        XCTAssertEqual(TokenFormatter.costString(100), "$100")
        XCTAssertEqual(TokenFormatter.costString(1234.6), "$1235")
    }

    func testCostStringClampsNegativeNaNAndInfinity() {
        XCTAssertEqual(TokenFormatter.costString(-5), "$0.00")
        XCTAssertEqual(TokenFormatter.costString(.nan), "$0.00")
        XCTAssertEqual(TokenFormatter.costString(.infinity), "$0.00")
        XCTAssertEqual(TokenFormatter.costString(-.infinity), "$0.00")
    }
}

// MARK: - Burn-rate string (Phase 2)

extension TokenFormatterTests {
    private func burnRate(
        tokensPerHour: Double,
        costPerHourUSD: Double,
        costPerDayUSD: Double
    ) -> TokenBurnRateBreakdown {
        TokenBurnRateBreakdown(
            tokensPerHour: tokensPerHour,
            costPerHourUSD: costPerHourUSD,
            costPerDayUSD: costPerDayUSD
        )
    }

    func testBurnRateStringRendersExactEnglishForm() {
        let breakdown = burnRate(tokensPerHour: 123_400, costPerHourUSD: 0.85, costPerDayUSD: 20.40)

        XCTAssertEqual(
            TokenFormatter.burnRateString(breakdown, language: .english),
            "123.4k/h · $0.85/h · ~$20.4/day"
        )
    }

    func testBurnRateStringLocalizesPerDaySuffixInPortuguese() {
        let breakdown = burnRate(tokensPerHour: 123_400, costPerHourUSD: 0.85, costPerDayUSD: 20.40)

        XCTAssertEqual(
            TokenFormatter.burnRateString(breakdown, language: .portuguese),
            "123.4k/h · $0.85/h · ~$20.4/dia"
        )
    }

    func testBurnRateStringSubCentCostPerHourUsesInheritedForm() {
        let breakdown = burnRate(tokensPerHour: 500, costPerHourUSD: 0.004, costPerDayUSD: 0.096)

        XCTAssertEqual(
            TokenFormatter.burnRateString(breakdown, language: .english),
            "500/h · < $0.01/h · ~$0.10/day"
        )
    }

    func testBurnRateStringSmallTokenRateRendersWithoutKSuffix() {
        let breakdown = burnRate(tokensPerHour: 950.4, costPerHourUSD: 0.02, costPerDayUSD: 0.48)

        XCTAssertTrue(TokenFormatter.burnRateString(breakdown, language: .english).hasPrefix("950/h"))
    }

    func testBurnRateStringZeroBreakdownNeverRendersNaNOrDash() {
        let zero = burnRate(tokensPerHour: 0, costPerHourUSD: 0, costPerDayUSD: 0)

        XCTAssertEqual(
            TokenFormatter.burnRateString(zero, language: .english),
            "0/h · $0.00/h · ~$0.00/day"
        )
    }

    func testBurnRateStringClampsPathologicalValues() {
        let pathological = burnRate(tokensPerHour: .nan, costPerHourUSD: -3, costPerDayUSD: .infinity)

        XCTAssertEqual(
            TokenFormatter.burnRateString(pathological, language: .english),
            "0/h · $0.00/h · ~$0.00/day"
        )
    }
}

// MARK: - Rate-limit strings (Phase 3)

extension TokenFormatterTests {
    /// 2026-06-12 00:00:00 UTC; blocks built backwards from a 17:30 UTC end.
    private var blockEnd: Date { Date(timeIntervalSinceReferenceDate: 802_915_200 + 17.5 * 3_600) }

    private func block(usageTokens: Int, costUSD: Double) -> TokenRateLimitBlock {
        TokenRateLimitBlock(
            start: blockEnd.addingTimeInterval(-5 * 3_600),
            end: blockEnd,
            usage: TokenAggregate(input: usageTokens, output: 0, cacheRead: 0, cacheCreation: 0),
            costUSD: costUSD
        )
    }

    private var utc: TimeZone { TimeZone(identifier: "UTC")! }

    func testLimitBlockStringRendersUsageCostAndResetInBothLanguages() {
        let block = block(usageTokens: 1_234_000, costUSD: 4.10)

        XCTAssertEqual(
            TokenFormatter.limitBlockString(block, language: .english, locale: Locale(identifier: "en_GB"), timeZone: utc),
            "1.2M · ~$4.10 · resets 17:30"
        )
        XCTAssertEqual(
            TokenFormatter.limitBlockString(block, language: .portuguese, locale: Locale(identifier: "pt_BR"), timeZone: utc),
            "1.2M · ~$4.10 · reinicia 17:30"
        )
    }

    func testLimitBlockStringResetTimeFollowsLocaleHourConvention() {
        let block = block(usageTokens: 500, costUSD: 0.02)
        let locale = Locale(identifier: "en_US")   // 12h convention

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = utc
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let expected = formatter.string(from: block.end)

        XCTAssertTrue(
            TokenFormatter.limitBlockString(block, language: .english, locale: locale, timeZone: utc)
                .hasSuffix("resets \(expected)")
        )
    }

    func testLimitWeeklyStringRendersHumanizedUsageAndCost() {
        let usage = TokenAggregate(input: 8_400_000, output: 0, cacheRead: 1, cacheCreation: 1)

        // Cache excluded from the headline figure; $31.2 renders with one decimal.
        XCTAssertEqual(TokenFormatter.limitWeeklyString(usage: usage, costUSD: 31.2), "8.4M · ~$31.2")
    }

    func testBudgetPercentClampsAndFlagsOverBudget() {
        XCTAssertEqual(TokenFormatter.budgetPercentString(usage: 1_000_000, budget: 2_000_000, language: .english), "50%")
        XCTAssertEqual(TokenFormatter.budgetPercentString(usage: 2_000_000, budget: 2_000_000, language: .english), "100%")
        XCTAssertEqual(
            TokenFormatter.budgetPercentString(usage: 3_000_000, budget: 2_000_000, language: .english),
            "100% · over budget"
        )
        XCTAssertEqual(
            TokenFormatter.budgetPercentString(usage: 3_000_000, budget: 2_000_000, language: .portuguese),
            "100% · acima do orçamento"
        )
        XCTAssertNil(TokenFormatter.budgetPercentString(usage: 1_000_000, budget: 0, language: .english))
    }

    func testBudgetFractionClampsToUnitRangeAndOffAtZeroBudget() {
        XCTAssertEqual(TokenFormatter.budgetFraction(usage: 1_000_000, budget: 2_000_000) ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(TokenFormatter.budgetFraction(usage: 3_000_000, budget: 2_000_000) ?? -1, 1, accuracy: 1e-9)
        XCTAssertEqual(TokenFormatter.budgetFraction(usage: -5, budget: 2_000_000) ?? -1, 0, accuracy: 1e-9)
        XCTAssertNil(TokenFormatter.budgetFraction(usage: 1, budget: 0))
        XCTAssertNil(TokenFormatter.budgetFraction(usage: 1, budget: -10))
    }

    func testLimitStringsNeverRenderNaNOrNegativeText() {
        let pathological = TokenRateLimitBlock(
            start: blockEnd.addingTimeInterval(-5 * 3_600),
            end: blockEnd,
            usage: TokenAggregate(input: -100, output: 0, cacheRead: 0, cacheCreation: 0),
            costUSD: .nan
        )

        let rendered = TokenFormatter.limitBlockString(pathological, language: .english, locale: Locale(identifier: "en_GB"), timeZone: utc)
        XCTAssertEqual(rendered, "0 · ~$0.00 · resets 17:30")
        XCTAssertFalse(rendered.contains("NaN"))

        let weekly = TokenFormatter.limitWeeklyString(usage: .zero, costUSD: -7)
        XCTAssertEqual(weekly, "0 · ~$0.00")

        XCTAssertEqual(TokenFormatter.budgetPercentString(usage: -50, budget: 100, language: .english), "0%")
    }
}
