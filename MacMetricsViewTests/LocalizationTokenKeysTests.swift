import XCTest
@testable import MacMetricsView

final class LocalizationTokenKeysTests: XCTestCase {
    func testAllTokenAccessorsReturnNonEmptyStringsInBothLanguages() {
        let texts: [LocalizedText] = [
            Strings.tokens,
            Strings.tokenInput,
            Strings.tokenOutput,
            Strings.tokenReasoning,
            Strings.tokenCache,
            Strings.tokenProviderLabel,
            Strings.tokenProviderClaude,
            Strings.tokenProviderCodex,
            Strings.tokenProviderCombined,
            Strings.tokenReset,
            Strings.tokenEmptyState,
            Strings.tokenScopeLabel,
            Strings.tokenScopeGlobal,
            Strings.tokenScopeProject,
            Strings.tokenScopeSession,
            Strings.tokenWindowLabel,
            Strings.tokenWindowToday,
            Strings.tokenWindowLastHour,
            Strings.tokenWindowLast24h,
            Strings.tokenWindowSinceReset,
            Strings.tokenSourceHelpTitle,
            Strings.tokenSourceHelp,
            Strings.tokenCostLabel,
            Strings.tokenCostEstimatedNote,
            Strings.tokenCostUnpricedNote,
            Strings.tokenPaceLabel,
            Strings.tokenPerDayUnit
        ]

        for text in texts {
            XCTAssertFalse(text(.english).isEmpty)
            XCTAssertFalse(text(.portuguese).isEmpty)
        }
    }

    func testLabelResetAndEmptyStateDifferBetweenLanguagesWhereExpected() {
        // Reset action and empty state are real phrases that translate.
        XCTAssertNotEqual(Strings.tokenReset(.english), Strings.tokenReset(.portuguese))
        XCTAssertNotEqual(Strings.tokenEmptyState(.english), Strings.tokenEmptyState(.portuguese))
        // "Tokens" is a loanword and reads the same in both.
        XCTAssertEqual(Strings.tokens(.english), Strings.tokens(.portuguese))
    }

    func testScopeAndWindowNameHelpersMapEveryCase() {
        XCTAssertEqual(Strings.tokenScopeName(.global)(.english), Strings.tokenScopeGlobal(.english))
        XCTAssertEqual(Strings.tokenScopeName(.project)(.portuguese), Strings.tokenScopeProject(.portuguese))
        XCTAssertEqual(Strings.tokenScopeName(.session)(.english), Strings.tokenScopeSession(.english))

        XCTAssertEqual(Strings.tokenWindowName(.today)(.english), Strings.tokenWindowToday(.english))
        XCTAssertEqual(Strings.tokenWindowName(.lastHour)(.portuguese), Strings.tokenWindowLastHour(.portuguese))
        XCTAssertEqual(Strings.tokenWindowName(.last24h)(.english), Strings.tokenWindowLast24h(.english))
        XCTAssertEqual(Strings.tokenWindowName(.sinceReset)(.english), Strings.tokenWindowSinceReset(.english))
    }

    func testReasoningAndProviderNamesResolveInBothLanguages() {
        XCTAssertEqual(Strings.tokenReasoning(.english), "Reasoning")
        XCTAssertEqual(Strings.tokenReasoning(.portuguese), "Raciocínio")

        XCTAssertEqual(Strings.tokenProviderClaude(.english), "Claude")
        XCTAssertEqual(Strings.tokenProviderCodex(.english), "Codex")
        XCTAssertEqual(Strings.tokenProviderCombined(.english), "Combined")
        // "Combined" is the only provider name that translates.
        XCTAssertNotEqual(Strings.tokenProviderCombined(.english), Strings.tokenProviderCombined(.portuguese))
        XCTAssertEqual(Strings.tokenProviderClaude(.english), Strings.tokenProviderClaude(.portuguese))
    }

    func testCostStringsCarryTheEstimatedQualifierInBothLanguages() {
        XCTAssertTrue(Strings.tokenCostLabel(.english).localizedCaseInsensitiveContains("est"))
        XCTAssertTrue(Strings.tokenCostLabel(.portuguese).localizedCaseInsensitiveContains("est"))
        XCTAssertTrue(Strings.tokenCostEstimatedNote(.english).localizedCaseInsensitiveContains("estimated"))
        XCTAssertTrue(Strings.tokenCostEstimatedNote(.portuguese).localizedCaseInsensitiveContains("estimativa"))
        // Cost strings are real phrases that translate.
        XCTAssertNotEqual(Strings.tokenCostEstimatedNote(.english), Strings.tokenCostEstimatedNote(.portuguese))
        XCTAssertNotEqual(Strings.tokenCostUnpricedNote(.english), Strings.tokenCostUnpricedNote(.portuguese))
    }

    func testPaceStringsTranslateBetweenLanguages() {
        // Pace label and per-day unit are real words that translate (Phase 2).
        XCTAssertEqual(Strings.tokenPaceLabel(.english), "Pace")
        XCTAssertEqual(Strings.tokenPaceLabel(.portuguese), "Ritmo")
        XCTAssertNotEqual(Strings.tokenPaceLabel(.english), Strings.tokenPaceLabel(.portuguese))

        XCTAssertEqual(Strings.tokenPerDayUnit(.english), "day")
        XCTAssertEqual(Strings.tokenPerDayUnit(.portuguese), "dia")
        XCTAssertNotEqual(Strings.tokenPerDayUnit(.english), Strings.tokenPerDayUnit(.portuguese))
    }

    func testProviderNameHelperMapsEverySelection() {
        XCTAssertEqual(Strings.tokenProviderName(.claude)(.english), Strings.tokenProviderClaude(.english))
        XCTAssertEqual(Strings.tokenProviderName(.codex)(.english), Strings.tokenProviderCodex(.english))
        XCTAssertEqual(Strings.tokenProviderName(.combined)(.portuguese), Strings.tokenProviderCombined(.portuguese))
    }
}
