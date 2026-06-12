import XCTest
@testable import MacMetricsView

final class TokenPricingTests: XCTestCase {

    // MARK: - Claude families resolve with current rates

    func testOpusCurrentGenerationResolvesTo5And25() {
        let rates = TokenPricing.rates(for: "claude-opus-4-8")
        XCTAssertEqual(rates?.inputPerMTok, 5)
        XCTAssertEqual(rates?.outputPerMTok, 25)
    }

    func testSonnetResolvesTo3And15() {
        let rates = TokenPricing.rates(for: "claude-sonnet-4-6")
        XCTAssertEqual(rates?.inputPerMTok, 3)
        XCTAssertEqual(rates?.outputPerMTok, 15)
    }

    func testHaiku45ResolvesTo1And5() {
        let rates = TokenPricing.rates(for: "claude-haiku-4-5")
        XCTAssertEqual(rates?.inputPerMTok, 1)
        XCTAssertEqual(rates?.outputPerMTok, 5)
    }

    func testFableResolvesTo10And50() {
        let rates = TokenPricing.rates(for: "claude-fable-5")
        XCTAssertEqual(rates?.inputPerMTok, 10)
        XCTAssertEqual(rates?.outputPerMTok, 50)
    }

    // MARK: - Version-sensitive Claude entries

    func testLegacyOpusBeforeFourPointFiveBillsAt15And75() {
        XCTAssertEqual(TokenPricing.rates(for: "claude-opus-4-1")?.inputPerMTok, 15)
        XCTAssertEqual(TokenPricing.rates(for: "claude-3-opus-20240229")?.outputPerMTok, 75)
    }

    func testOpusFourPointFiveAndLaterBillAt5And25() {
        XCTAssertEqual(TokenPricing.rates(for: "claude-opus-4-5-20251101")?.inputPerMTok, 5)
        XCTAssertEqual(TokenPricing.rates(for: "claude-opus-4-6")?.inputPerMTok, 5)
    }

    func testLegacyHaikuTiers() {
        XCTAssertEqual(TokenPricing.rates(for: "claude-3-5-haiku-20241022")?.inputPerMTok, 0.8)
        XCTAssertEqual(TokenPricing.rates(for: "claude-3-haiku-20240307")?.inputPerMTok, 0.25)
    }

    // MARK: - Date-suffixed ids resolve to the family entry

    func testDateSuffixedIdResolvesSameAsAlias() {
        XCTAssertEqual(
            TokenPricing.rates(for: "claude-haiku-4-5-20251001"),
            TokenPricing.rates(for: "claude-haiku-4-5")
        )
    }

    // MARK: - Anthropic cache rate relationships

    func testAnthropicCacheReadIsTenPercentOfInput() {
        for id in ["claude-opus-4-8", "claude-sonnet-4-6", "claude-haiku-4-5", "claude-fable-5"] {
            let rates = TokenPricing.rates(for: id)!
            XCTAssertEqual(rates.cacheReadPerMTok, rates.inputPerMTok * 0.1, accuracy: 1e-9, id)
            XCTAssertEqual(rates.cacheWritePerMTok, rates.inputPerMTok * 1.25, accuracy: 1e-9, id)
        }
    }

    // MARK: - OpenAI (Codex) entries

    func testGPT5CodexResolvesToGPT5Rates() {
        let rates = TokenPricing.rates(for: "gpt-5-codex")
        XCTAssertEqual(rates?.inputPerMTok, 1.25)
        XCTAssertEqual(rates?.outputPerMTok, 10)
        XCTAssertEqual(rates?.cacheReadPerMTok, 0.125)
    }

    func testGPT5MiniAndNanoResolveToTheirOwnTiers() {
        XCTAssertEqual(TokenPricing.rates(for: "gpt-5-mini")?.inputPerMTok, 0.25)
        XCTAssertEqual(TokenPricing.rates(for: "gpt-5-nano")?.inputPerMTok, 0.05)
    }

    func testOSeriesEntries() {
        XCTAssertEqual(TokenPricing.rates(for: "o3")?.inputPerMTok, 2)
        XCTAssertEqual(TokenPricing.rates(for: "o3-mini")?.inputPerMTok, 1.1)
        XCTAssertEqual(TokenPricing.rates(for: "o4-mini")?.inputPerMTok, 1.1)
        XCTAssertEqual(TokenPricing.rates(for: "o4-mini")?.cacheReadPerMTok, 0.275)
    }

    func testOpenAICacheWriteCarriesNoPremium() {
        let rates = TokenPricing.rates(for: "gpt-5-codex")!
        XCTAssertEqual(rates.cacheWritePerMTok, rates.inputPerMTok)
    }

    // MARK: - Unknown ids never get a guessed price

    func testUnknownVendorReturnsNil() {
        XCTAssertNil(TokenPricing.rates(for: "mystery-model-9"))
        XCTAssertNil(TokenPricing.rates(for: "gemini-2.5-pro"))
    }

    func testEmptyAndSyntheticIdsReturnNil() {
        XCTAssertNil(TokenPricing.rates(for: ""))
        XCTAssertNil(TokenPricing.rates(for: "   "))
        XCTAssertNil(TokenPricing.rates(for: "<synthetic>"))
    }

    func testCaseAndWhitespaceInsensitive() {
        XCTAssertEqual(
            TokenPricing.rates(for: "  Claude-Opus-4-8 "),
            TokenPricing.rates(for: "claude-opus-4-8")
        )
    }
}
