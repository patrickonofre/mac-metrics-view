import XCTest
@testable import MacMetricsView

/// Verifies the data and control targets the popover token row binds to. The SwiftUI
/// layout itself is verified by launching the app, per the project's testing standards;
/// here we assert the `CPUState` surfaces (breakdown, row value, sparkline) and the
/// setters/reset the pickers and Reset button invoke.
@MainActor
final class PopoverTokenRowTests: XCTestCase {
    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "MacMetricsViewTests.PopoverToken.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        ud.removePersistentDomain(forName: suiteName)
        return ud
    }

    private func event(at date: Date = Date(), input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheCreation: Int = 0) -> TokenUsageEvent {
        TokenUsageEvent(
            timestamp: date,
            model: "claude-opus-4-8",
            inputTokens: input,
            outputTokens: output,
            cacheReadTokens: cacheRead,
            cacheCreationTokens: cacheCreation,
            sessionID: "s1.jsonl",
            projectDir: "p1"
        )
    }

    private func codexEvent(at date: Date = Date(), input: Int = 0, output: Int = 0, reasoning: Int = 0) -> TokenUsageEvent {
        TokenUsageEvent(
            timestamp: date,
            model: "gpt-5-codex",
            inputTokens: input,
            outputTokens: output,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            reasoningTokens: reasoning,
            sessionID: "cx1",
            projectDir: "/cx"
        )
    }

    // MARK: - Row content

    func testBreakdownRowReflectsAggregate() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(with: [event(input: 1_000, output: 2_000, cacheRead: 1_500, cacheCreation: 1_500)])

        let rows = state.token.breakdown
        XCTAssertEqual(rows.map(\.label), [Strings.tokenInput(), Strings.tokenOutput(), Strings.tokenCache()])
        XCTAssertEqual(rows.map(\.value), ["1.0k", "2.0k", "3.0k"])   // cache = read + creation
    }

    func testRowValueShowsHumanizedTotalWhenData() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(with: [event(input: 12_300)])

        XCTAssertFalse(state.token.isEmpty)
        XCTAssertEqual(state.token.rowValue, "12.3k")
    }

    func testRowValueExcludesCacheButBreakdownKeepsIt() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(with: [event(input: 1_000, output: 2_000, cacheRead: 5_000, cacheCreation: 5_000)])

        // Headline = input + output only.
        XCTAssertEqual(state.token.rowValue, "3.0k")
        // Popover breakdown still shows the cache total (read + creation = 10k).
        XCTAssertEqual(state.token.breakdown.map(\.value), ["1.0k", "2.0k", "10.0k"])
    }

    func testRowValueShowsLocalizedEmptyStateWhenNoData() {
        let state = CPUState(userDefaults: makeUserDefaults())

        XCTAssertTrue(state.token.isEmpty)
        XCTAssertEqual(state.token.rowValue, Strings.tokenEmptyState())
        XCTAssertNotEqual(state.token.rowValue, "0")
        XCTAssertTrue(state.token.sparkline.isEmpty)   // no flat-line noise
    }

    func testSparklineIsNormalizedToPeak() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(with: [
            event(at: Date().addingTimeInterval(-30 * 60), input: 100),
            event(at: Date(), input: 400)
        ])

        let sparkline = state.token.sparkline
        XCTAssertFalse(sparkline.isEmpty)
        XCTAssertEqual(sparkline.max(), 100)
    }

    // MARK: - Control bindings

    func testScopePickerSetterChangesStateAndPersists() {
        let userDefaults = makeUserDefaults()
        let state = CPUState(userDefaults: userDefaults)

        state.setTokenScope(.session)

        XCTAssertEqual(state.tokenScope, .session)
        XCTAssertEqual(MetricDisplaySettings.load(from: userDefaults).tokenScope, .session)
    }

    func testWindowPickerSetterUpdatesAggregateAndPersists() {
        let userDefaults = makeUserDefaults()
        let state = CPUState(userDefaults: userDefaults)
        state.update(with: [
            event(at: Date().addingTimeInterval(-2 * 3_600), input: 50),
            event(at: Date(), input: 10)
        ])

        state.setTokenMenuBarWindow(.last24h)

        XCTAssertEqual(state.token.aggregate.input, 60)
        XCTAssertEqual(MetricDisplaySettings.load(from: userDefaults).tokenMenuBarWindow, .last24h)
    }

    func testResetButtonZeroesSinceResetImmediately() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(with: [event(input: 100)])
        state.setTokenMenuBarWindow(.sinceReset)
        XCTAssertEqual(state.token.aggregate.input, 100)

        state.resetTokenCounter()

        XCTAssertEqual(state.token.aggregate.input, 0)
    }

    // MARK: - Provider picker (task_09)

    func testProviderPickerSetterChangesStateAndPersists() {
        let userDefaults = makeUserDefaults()
        let state = CPUState(userDefaults: userDefaults)

        state.setTokenProvider(.codex)

        XCTAssertEqual(state.tokenProvider, .codex)
        XCTAssertEqual(MetricDisplaySettings.load(from: userDefaults).tokenProvider, .codex)
    }

    func testBreakdownShowsReasoningRowOnlyForCodexAggregate() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(provider: .claude, with: [event(input: 1_000, output: 500)])
        state.update(provider: .codex, with: [codexEvent(input: 300, output: 100, reasoning: 200)])

        state.setTokenProvider(.codex)
        XCTAssertTrue(state.token.breakdown.map(\.label).contains(Strings.tokenReasoning()))

        state.setTokenProvider(.claude)
        XCTAssertFalse(state.token.breakdown.map(\.label).contains(Strings.tokenReasoning()))
    }

    func testRowContentFollowsSelectedProvider() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(provider: .claude, with: [event(input: 1_000)])
        state.update(provider: .codex, with: [codexEvent(input: 3_000)])

        state.setTokenProvider(.claude)
        XCTAssertEqual(state.token.rowValue, "1.0k")
        XCTAssertEqual(state.token.activeModels, "Opus 4.8")

        state.setTokenProvider(.codex)
        XCTAssertEqual(state.token.rowValue, "3.0k")
        XCTAssertEqual(state.token.activeModels, "GPT-5 Codex")
    }

    func testEmptyStateShownForProviderWithNoLogs() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(provider: .claude, with: [event(input: 1_000)])

        // Codex selected but no Codex logs → empty/zero state, not an error or stale Claude data.
        state.setTokenProvider(.codex)
        XCTAssertTrue(state.token.isEmpty)
        XCTAssertEqual(state.token.rowValue, Strings.tokenEmptyState())
        XCTAssertTrue(state.token.sparkline.isEmpty)
    }

    // MARK: - Estimated cost row (Phase 1)

    func testCostRowValueNilWithoutEventsSoTheRowHides() {
        let state = CPUState(userDefaults: makeUserDefaults())

        XCTAssertNil(state.token.costRowValue)
        XCTAssertTrue(state.token.costPerModel.isEmpty)
        XCTAssertFalse(state.token.costHasUnpricedTokens)
    }

    func testCostRowValueFormatsTheBreakdownTotal() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(with: [event(input: 1_000_000, output: 100_000)])   // $5 + $2.50

        XCTAssertEqual(state.token.costRowValue, "$7.50")
    }

    func testCostPerModelPairsFriendlyNamesWithFormattedValuesLargestFirst() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(provider: .claude, with: [event(input: 1_000_000)])        // $5
        state.update(provider: .codex, with: [codexEvent(input: 1_000_000)])    // $1.25

        let perModel = state.token.costPerModel
        XCTAssertEqual(perModel.map { $0.label }, ["Opus 4.8", "GPT-5 Codex"])
        XCTAssertEqual(perModel.map { $0.value }, ["$5.00", "$1.25"])
    }

    func testUnpricedIndicatorConditionFollowsUnpricedTokens() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(with: [event(input: 1_000_000)])
        XCTAssertFalse(state.token.costHasUnpricedTokens)

        state.update(with: [TokenUsageEvent(
            timestamp: Date(),
            model: "mystery-model-9",
            inputTokens: 100,
            outputTokens: 0,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            sessionID: "s1.jsonl",
            projectDir: "p1"
        )])
        XCTAssertTrue(state.token.costHasUnpricedTokens)
    }

    func testSubCentUsageRendersTheSubCentForm() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(with: [event(input: 100)])   // 100 tokens × $5/MTok = $0.0005

        XCTAssertEqual(state.token.costRowValue, "< $0.01")
    }

    // MARK: - Pace row (Phase 2)

    func testPaceRowValueNilWithoutBurnRateSoTheRowHides() {
        let state = CPUState(userDefaults: makeUserDefaults())

        XCTAssertNil(state.token.burnRate)
        XCTAssertNil(state.token.paceRowValue)
    }

    func testPaceRowValueMatchesFormatterOutputExactly() throws {
        // No double formatting: the helper must be exactly the task_02 string for the
        // published breakdown.
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(with: [event(at: Date().addingTimeInterval(-300), input: 1_000_000, output: 200_000)])

        let breakdown = try XCTUnwrap(state.token.burnRate)
        XCTAssertEqual(state.token.paceRowValue, TokenFormatter.burnRateString(breakdown))
    }

    func testPaceLabelResolvesPerLanguage() {
        XCTAssertEqual(Strings.tokenPaceLabel(.english), "Pace")
        XCTAssertEqual(Strings.tokenPaceLabel(.portuguese), "Ritmo")
    }

    func testPaceLifecycleFreshOnAppearAndDeadAfterDisappear() {
        let state = CPUState(userDefaults: makeUserDefaults())

        // Simulated appear: begin starts the refresh; ingest lands fresh data.
        state.beginTokenAutoRefresh()
        state.update(with: [event(input: 120_000)])
        XCTAssertNotNil(state.token.paceRowValue)

        // Simulated disappear: end kills the timer; a time-advanced tick no longer
        // fires, so the pace row keeps its last value instead of decaying.
        state.endTokenAutoRefresh()
        state.tokenAutoRefreshTick(now: Date().addingTimeInterval(61 * 60))
        XCTAssertNotNil(state.token.paceRowValue)
    }

    func testPaceDecaysWhileOpenViaTick() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(with: [event(input: 120_000)])
        state.beginTokenAutoRefresh()
        defer { state.endTokenAutoRefresh() }

        state.tokenAutoRefreshTick(now: Date().addingTimeInterval(61 * 60))

        XCTAssertNil(state.token.paceRowValue)   // row hides once the hour empties
    }

    func testTokenRowDataSurvivesMenuBarVisibilityOff() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.metrics.setTokenVisible(false)   // hidden from the menu bar
        state.update(with: [event(input: 100)])

        // The popover row binds to these regardless of menu-bar visibility.
        XCTAssertFalse(state.token.isEmpty)
        XCTAssertEqual(state.token.rowValue, "100")
        XCTAssertFalse(state.metrics.visibility.showTokens)
    }
}
