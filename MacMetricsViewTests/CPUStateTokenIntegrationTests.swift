import XCTest
@testable import MacMetricsView

@MainActor
final class CPUStateTokenIntegrationTests: XCTestCase {
    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "MacMetricsViewTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }

    private func event(
        at date: Date = Date(),
        input: Int = 0,
        output: Int = 0,
        cacheRead: Int = 0,
        cacheCreation: Int = 0,
        session: String = "s1.jsonl",
        project: String = "p1"
    ) -> TokenUsageEvent {
        TokenUsageEvent(
            timestamp: date,
            model: "claude-opus-4-8",
            inputTokens: input,
            outputTokens: output,
            cacheReadTokens: cacheRead,
            cacheCreationTokens: cacheCreation,
            sessionID: session,
            projectDir: project
        )
    }

    // MARK: - Ingest → publish

    func testUpdateWithEventsPublishesTodayGlobalAggregate() {
        let state = CPUState(userDefaults: makeUserDefaults())

        state.update(with: [event(input: 100)])

        XCTAssertEqual(state.tokenAggregate.input, 100)   // default scope global, window today
        XCTAssertEqual(state.tokenAggregate.total, 100)
    }

    // MARK: - Scope

    func testSetTokenScopeRecomputesToMRUSessionAndPersists() {
        let userDefaults = makeUserDefaults()
        let state = CPUState(userDefaults: userDefaults)
        // Newest event (MRU) is session s2.
        state.update(with: [
            event(at: Date().addingTimeInterval(-120), input: 10, session: "s1", project: "p1"),
            event(at: Date(), input: 40, session: "s2", project: "p2")
        ])

        state.setTokenScope(.session)

        XCTAssertEqual(state.tokenScope, .session)
        XCTAssertEqual(state.tokenAggregate.input, 40)   // s2 only
        XCTAssertEqual(MetricDisplaySettings.load(from: userDefaults).tokenScope, .session)
    }

    // MARK: - Window

    func testSetTokenMenuBarWindowRepublishesForThatWindow() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(with: [
            event(at: Date().addingTimeInterval(-2 * 3_600), input: 50),  // 2h ago
            event(at: Date(), input: 10)                                   // now
        ])

        state.setTokenMenuBarWindow(.lastHour)
        XCTAssertEqual(state.tokenAggregate.input, 10)

        state.setTokenMenuBarWindow(.last24h)
        XCTAssertEqual(state.tokenAggregate.input, 60)
    }

    // MARK: - Reset

    func testResetTokenCounterZeroesSinceResetButLeavesRollingWindows() {
        let userDefaults = makeUserDefaults()
        let state = CPUState(userDefaults: userDefaults)
        state.update(with: [event(input: 100)])

        state.setTokenMenuBarWindow(.sinceReset)
        XCTAssertEqual(state.tokenAggregate.input, 100)

        state.resetTokenCounter()
        XCTAssertEqual(state.tokenAggregate.input, 0)              // since-reset zeroed
        XCTAssertNotNil(userDefaults.object(forKey: "CPUState.tokenResetAt"))

        state.setTokenMenuBarWindow(.last24h)
        XCTAssertEqual(state.tokenAggregate.input, 100)           // rolling window unaffected
    }

    // MARK: - Visibility vs ingestion

    func testIngestionWorksWhileTokenHiddenFromMenuBar() {
        let state = CPUState(userDefaults: makeUserDefaults())
        // showTokens defaults to false.
        state.update(with: [event(input: 100)])

        XCTAssertEqual(state.tokenAggregate.input, 100)
        XCTAssertFalse(state.visibleMenuBarTitles.contains { $0.contains("TOK") })
    }

    func testVisibleMenuBarTitlesIncludesTokenSegmentWhenVisible() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.setMetricIdentifierStyle(.labels)
        state.setTokenVisible(true)
        state.update(with: [event(input: 1_500)])

        XCTAssertTrue(state.visibleMenuBarTitles.contains { $0.contains("TOK") })
    }

    // MARK: - Integration: title reflects humanized count

    func testVisibleMenuBarTitleReflectsHumanizedCountForSelectedWindow() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.setTokenVisible(true)   // identifier style defaults to icons → count only
        state.update(with: [event(input: 1_500)])

        XCTAssertTrue(state.visibleMenuBarTitles.contains("1.5k"))
    }

    func testAccessibilityMenuBarTitleIncludesTokenWordingWhenVisible() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.setTokenVisible(true)
        state.update(with: [event(input: 100)])

        XCTAssertTrue(state.accessibilityMenuBarTitle.contains(Strings.tokens()))
    }
}
