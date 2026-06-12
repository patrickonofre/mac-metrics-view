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

        let rows = state.tokenBreakdown
        XCTAssertEqual(rows.map(\.label), [Strings.tokenInput(), Strings.tokenOutput(), Strings.tokenCache()])
        XCTAssertEqual(rows.map(\.value), ["1.0k", "2.0k", "3.0k"])   // cache = read + creation
    }

    func testRowValueShowsHumanizedTotalWhenData() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(with: [event(input: 12_300)])

        XCTAssertFalse(state.tokenIsEmpty)
        XCTAssertEqual(state.tokenRowValue, "12.3k")
    }

    func testRowValueExcludesCacheButBreakdownKeepsIt() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(with: [event(input: 1_000, output: 2_000, cacheRead: 5_000, cacheCreation: 5_000)])

        // Headline = input + output only.
        XCTAssertEqual(state.tokenRowValue, "3.0k")
        // Popover breakdown still shows the cache total (read + creation = 10k).
        XCTAssertEqual(state.tokenBreakdown.map(\.value), ["1.0k", "2.0k", "10.0k"])
    }

    func testRowValueShowsLocalizedEmptyStateWhenNoData() {
        let state = CPUState(userDefaults: makeUserDefaults())

        XCTAssertTrue(state.tokenIsEmpty)
        XCTAssertEqual(state.tokenRowValue, Strings.tokenEmptyState())
        XCTAssertNotEqual(state.tokenRowValue, "0")
        XCTAssertTrue(state.tokenSparkline.isEmpty)   // no flat-line noise
    }

    func testSparklineIsNormalizedToPeak() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(with: [
            event(at: Date().addingTimeInterval(-30 * 60), input: 100),
            event(at: Date(), input: 400)
        ])

        let sparkline = state.tokenSparkline
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

        XCTAssertEqual(state.tokenAggregate.input, 60)
        XCTAssertEqual(MetricDisplaySettings.load(from: userDefaults).tokenMenuBarWindow, .last24h)
    }

    func testResetButtonZeroesSinceResetImmediately() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(with: [event(input: 100)])
        state.setTokenMenuBarWindow(.sinceReset)
        XCTAssertEqual(state.tokenAggregate.input, 100)

        state.resetTokenCounter()

        XCTAssertEqual(state.tokenAggregate.input, 0)
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
        XCTAssertTrue(state.tokenBreakdown.map(\.label).contains(Strings.tokenReasoning()))

        state.setTokenProvider(.claude)
        XCTAssertFalse(state.tokenBreakdown.map(\.label).contains(Strings.tokenReasoning()))
    }

    func testRowContentFollowsSelectedProvider() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(provider: .claude, with: [event(input: 1_000)])
        state.update(provider: .codex, with: [codexEvent(input: 3_000)])

        state.setTokenProvider(.claude)
        XCTAssertEqual(state.tokenRowValue, "1.0k")
        XCTAssertEqual(state.tokenActiveModels, "Opus 4.8")

        state.setTokenProvider(.codex)
        XCTAssertEqual(state.tokenRowValue, "3.0k")
        XCTAssertEqual(state.tokenActiveModels, "GPT-5 Codex")
    }

    func testEmptyStateShownForProviderWithNoLogs() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(provider: .claude, with: [event(input: 1_000)])

        // Codex selected but no Codex logs → empty/zero state, not an error or stale Claude data.
        state.setTokenProvider(.codex)
        XCTAssertTrue(state.tokenIsEmpty)
        XCTAssertEqual(state.tokenRowValue, Strings.tokenEmptyState())
        XCTAssertTrue(state.tokenSparkline.isEmpty)
    }

    // MARK: - Estimated cost row (Phase 1)

    func testCostRowValueNilWithoutEventsSoTheRowHides() {
        let state = CPUState(userDefaults: makeUserDefaults())

        XCTAssertNil(state.tokenCostRowValue)
        XCTAssertTrue(state.tokenCostPerModel.isEmpty)
        XCTAssertFalse(state.tokenCostHasUnpricedTokens)
    }

    func testCostRowValueFormatsTheBreakdownTotal() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(with: [event(input: 1_000_000, output: 100_000)])   // $5 + $2.50

        XCTAssertEqual(state.tokenCostRowValue, "$7.50")
    }

    func testCostPerModelPairsFriendlyNamesWithFormattedValuesLargestFirst() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(provider: .claude, with: [event(input: 1_000_000)])        // $5
        state.update(provider: .codex, with: [codexEvent(input: 1_000_000)])    // $1.25

        let perModel = state.tokenCostPerModel
        XCTAssertEqual(perModel.map { $0.label }, ["Opus 4.8", "GPT-5 Codex"])
        XCTAssertEqual(perModel.map { $0.value }, ["$5.00", "$1.25"])
    }

    func testUnpricedIndicatorConditionFollowsUnpricedTokens() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(with: [event(input: 1_000_000)])
        XCTAssertFalse(state.tokenCostHasUnpricedTokens)

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
        XCTAssertTrue(state.tokenCostHasUnpricedTokens)
    }

    func testSubCentUsageRendersTheSubCentForm() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(with: [event(input: 100)])   // 100 tokens × $5/MTok = $0.0005

        XCTAssertEqual(state.tokenCostRowValue, "< $0.01")
    }

    func testTokenRowDataSurvivesMenuBarVisibilityOff() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.setTokenVisible(false)   // hidden from the menu bar
        state.update(with: [event(input: 100)])

        // The popover row binds to these regardless of menu-bar visibility.
        XCTAssertFalse(state.tokenIsEmpty)
        XCTAssertEqual(state.tokenRowValue, "100")
        XCTAssertFalse(state.visibility.showTokens)
    }
}
