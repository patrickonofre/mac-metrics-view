import XCTest
@testable import MacMetricsView

final class TokenValueTypesTests: XCTestCase {

    // MARK: - TokenAggregate

    func testTokenAggregateTotalSumsAllFields() {
        let aggregate = TokenAggregate(input: 2, output: 3, cacheRead: 5, cacheCreation: 7)

        XCTAssertEqual(aggregate.total, 17)
    }

    func testTokenAggregateAllZeroHasZeroTotal() {
        let aggregate = TokenAggregate(input: 0, output: 0, cacheRead: 0, cacheCreation: 0)

        XCTAssertEqual(aggregate.total, 0)
    }

    func testTokenAggregateUsageTotalIsInputPlusOutputOnly() {
        let aggregate = TokenAggregate(input: 2, output: 3, cacheRead: 5, cacheCreation: 7)

        XCTAssertEqual(aggregate.total, 17)        // full sum (all four)
        XCTAssertEqual(aggregate.usageTotal, 5)    // headline excludes cache
    }

    func testTokenAggregateEquatableMatchesOnAllFields() {
        let lhs = TokenAggregate(input: 1, output: 2, cacheRead: 3, cacheCreation: 4)
        let rhs = TokenAggregate(input: 1, output: 2, cacheRead: 3, cacheCreation: 4)
        let different = TokenAggregate(input: 1, output: 2, cacheRead: 3, cacheCreation: 5)

        XCTAssertEqual(lhs, rhs)
        XCTAssertNotEqual(lhs, different)
    }

    // MARK: - TokenScope

    func testTokenScopeRawValueRoundTrips() {
        let cases: [(TokenScope, String)] = [
            (.global, "global"),
            (.project, "project"),
            (.session, "session")
        ]

        for (scope, raw) in cases {
            XCTAssertEqual(scope.rawValue, raw)
            XCTAssertEqual(TokenScope(rawValue: raw), scope)
        }
    }

    func testTokenScopeRejectsUnknownRawValue() {
        XCTAssertNil(TokenScope(rawValue: "machine"))
    }

    // MARK: - TokenWindow

    func testTokenWindowRawValueRoundTrips() {
        let cases: [(TokenWindow, String)] = [
            (.today, "today"),
            (.lastHour, "lastHour"),
            (.last24h, "last24h"),
            (.sinceReset, "sinceReset")
        ]

        for (window, raw) in cases {
            XCTAssertEqual(window.rawValue, raw)
            XCTAssertEqual(TokenWindow(rawValue: raw), window)
        }
    }

    func testTokenWindowRejectsUnknownRawValue() {
        XCTAssertNil(TokenWindow(rawValue: "lastWeek"))
    }

    // MARK: - TokenUsageEvent

    private func makeEvent(
        timestamp: Date = Date(timeIntervalSince1970: 1_000),
        model: String = "claude-opus-4-8",
        inputTokens: Int = 100,
        outputTokens: Int = 200,
        cacheReadTokens: Int = 300,
        cacheCreationTokens: Int = 400,
        sessionID: String = "session-a.jsonl",
        projectDir: String = "project-a"
    ) -> TokenUsageEvent {
        TokenUsageEvent(
            timestamp: timestamp,
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens,
            cacheCreationTokens: cacheCreationTokens,
            sessionID: sessionID,
            projectDir: projectDir
        )
    }

    func testTokenUsageEventEqualsWhenAllFieldsMatch() {
        XCTAssertEqual(makeEvent(), makeEvent())
    }

    func testTokenUsageEventDiffersWhenOneFieldDiffers() {
        let base = makeEvent()

        XCTAssertNotEqual(base, makeEvent(timestamp: Date(timeIntervalSince1970: 2_000)))
        XCTAssertNotEqual(base, makeEvent(model: "claude-sonnet-4-6"))
        XCTAssertNotEqual(base, makeEvent(inputTokens: 101))
        XCTAssertNotEqual(base, makeEvent(outputTokens: 201))
        XCTAssertNotEqual(base, makeEvent(cacheReadTokens: 301))
        XCTAssertNotEqual(base, makeEvent(cacheCreationTokens: 401))
        XCTAssertNotEqual(base, makeEvent(sessionID: "session-b.jsonl"))
        XCTAssertNotEqual(base, makeEvent(projectDir: "project-b"))
    }
}
