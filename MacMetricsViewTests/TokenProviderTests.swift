import XCTest
@testable import MacMetricsView

final class TokenProviderTests: XCTestCase {

    // MARK: - TokenProvider

    func testTokenProviderRawValueRoundTrips() {
        let cases: [(TokenProvider, String)] = [
            (.claude, "claude"),
            (.codex, "codex")
        ]

        for (provider, raw) in cases {
            XCTAssertEqual(provider.rawValue, raw)
            XCTAssertEqual(TokenProvider(rawValue: raw), provider)
        }
    }

    func testTokenProviderRejectsUnknownRawValue() {
        XCTAssertNil(TokenProvider(rawValue: "combined"))   // combined is never a stored provider
        XCTAssertNil(TokenProvider(rawValue: "opencode"))
    }

    // MARK: - TokenProviderSelection

    func testSelectionRawValueRoundTrips() {
        let cases: [(TokenProviderSelection, String)] = [
            (.claude, "claude"),
            (.codex, "codex"),
            (.combined, "combined")
        ]

        for (selection, raw) in cases {
            XCTAssertEqual(selection.rawValue, raw)
            // Simulate the persistence save→load round-trip via the raw string.
            XCTAssertEqual(TokenProviderSelection(rawValue: selection.rawValue), selection)
        }
    }

    func testSelectionUnknownRawFallsBackToCombined() {
        XCTAssertNil(TokenProviderSelection(rawValue: "garbage"))
        // The documented default contract a consumer applies on a bad stored value.
        XCTAssertEqual(TokenProviderSelection(rawValue: "garbage") ?? .combined, .combined)
    }

    func testRetiredGeminiSelectionFallsBackToCombined() {
        // Older builds persisted "gemini"; after its removal the value is unknown and
        // must decode to the default instead of crashing (migration contract).
        XCTAssertNil(TokenProviderSelection(rawValue: "gemini"))
        XCTAssertEqual(TokenProviderSelection(rawValue: "gemini") ?? .combined, .combined)
    }

    // MARK: - Aggregated providers

    func testCombinedAggregatesBothProviders() {
        XCTAssertEqual(TokenProviderSelection.combined.providers, [.claude, .codex])
    }

    func testSingleSelectionAggregatesOnlyItself() {
        XCTAssertEqual(TokenProviderSelection.claude.providers, [.claude])
        XCTAssertEqual(TokenProviderSelection.codex.providers, [.codex])
    }
}
