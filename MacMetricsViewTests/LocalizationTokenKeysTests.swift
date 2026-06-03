import XCTest
@testable import MacMetricsView

final class LocalizationTokenKeysTests: XCTestCase {
    func testAllTokenAccessorsReturnNonEmptyStringsInBothLanguages() {
        let texts: [LocalizedText] = [
            Strings.tokens,
            Strings.tokenInput,
            Strings.tokenOutput,
            Strings.tokenCache,
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
            Strings.tokenSourceHelp
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
}
