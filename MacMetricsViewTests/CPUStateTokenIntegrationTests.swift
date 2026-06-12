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
        // Default provider is combined → reset persists per-provider keys (both).
        XCTAssertNotNil(userDefaults.object(forKey: "CPUState.tokenResetAt.claude"))
        XCTAssertNotNil(userDefaults.object(forKey: "CPUState.tokenResetAt.codex"))

        state.setTokenMenuBarWindow(.last24h)
        XCTAssertEqual(state.tokenAggregate.input, 100)           // rolling window unaffected
    }

    // MARK: - Visibility vs ingestion

    func testIngestionWorksWhileTokenHiddenFromMenuBar() {
        let state = CPUState(userDefaults: makeUserDefaults())
        // showTokens defaults to false.
        state.update(with: [event(input: 100)])

        XCTAssertEqual(state.tokenAggregate.input, 100)   // ingested despite being hidden
        XCTAssertFalse(state.visibility.showTokens)        // no token segment in the menu bar
    }

    func testVisibleMenuBarTitlesIncludesTokenSegmentWhenVisible() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.setMetricIdentifierStyle(.labels)
        state.setTokenVisible(true)
        state.update(with: [event(input: 1_500)])

        // Default provider is combined → the label is the provider-aware name, not "TOK".
        let combinedLabel = TokenFormatter.menuBarLabel(for: .combined)
        XCTAssertTrue(state.visibleMenuBarTitles.contains { $0.contains(combinedLabel) && $0.contains("1.5k") })
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

    // MARK: - Provider dimension (task_06)

    private func codexEvent(
        at date: Date = Date(),
        input: Int = 0,
        output: Int = 0,
        reasoning: Int = 0,
        model: String = "gpt-5-codex",
        session: String = "cx1",
        project: String = "/cx"
    ) -> TokenUsageEvent {
        TokenUsageEvent(
            timestamp: date,
            model: model,
            inputTokens: input,
            outputTokens: output,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            reasoningTokens: reasoning,
            sessionID: session,
            projectDir: project
        )
    }

    func testUpdateRoutesToCorrectProviderStore() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(provider: .codex, with: [codexEvent(input: 70, reasoning: 5)])

        XCTAssertEqual(state.tokenStores[.codex]?.events.count, 1)
        XCTAssertEqual(state.tokenStores[.claude]?.events.count, 0)   // claude untouched
    }

    func testCombinedAggregateSumsBothProviders() {
        let state = CPUState(userDefaults: makeUserDefaults())   // default selection: combined
        state.update(provider: .claude, with: [event(input: 100, output: 200)])
        state.update(provider: .codex, with: [codexEvent(input: 10, output: 20, reasoning: 5)])

        XCTAssertEqual(state.tokenProvider, .combined)
        XCTAssertEqual(state.tokenAggregate.input, 110)
        XCTAssertEqual(state.tokenAggregate.output, 220)
        XCTAssertEqual(state.tokenAggregate.reasoning, 5)
        XCTAssertEqual(state.tokenAggregate.usageTotal, 110 + 220 + 5)
    }

    func testSetTokenProviderReflectsOnlyThatProvider() {
        let userDefaults = makeUserDefaults()
        let state = CPUState(userDefaults: userDefaults)
        state.update(provider: .claude, with: [event(input: 100)])
        state.update(provider: .codex, with: [codexEvent(input: 10, reasoning: 5)])

        state.setTokenProvider(.codex)
        XCTAssertEqual(state.tokenAggregate.input, 10)
        XCTAssertEqual(state.tokenAggregate.reasoning, 5)
        XCTAssertEqual(MetricDisplaySettings.load(from: userDefaults).tokenProvider, .codex)

        state.setTokenProvider(.claude)
        XCTAssertEqual(state.tokenAggregate.input, 100)
        XCTAssertEqual(state.tokenAggregate.reasoning, 0)
    }

    func testResetScopedToSelectedProvider() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(provider: .claude, with: [event(input: 100)])
        state.update(provider: .codex, with: [codexEvent(input: 40)])
        state.setTokenMenuBarWindow(.sinceReset)

        // Reset only Codex.
        state.setTokenProvider(.codex)
        state.resetTokenCounter()
        XCTAssertEqual(state.tokenAggregate.input, 0)              // codex since-reset zeroed
        state.setTokenProvider(.claude)
        XCTAssertEqual(state.tokenAggregate.input, 100)            // claude untouched

        // Reset both via combined.
        state.setTokenProvider(.combined)
        state.resetTokenCounter()
        XCTAssertEqual(state.tokenAggregate.input, 0)
    }

    func testPerProviderResetKeysPersistIndependently() {
        let userDefaults = makeUserDefaults()
        let state = CPUState(userDefaults: userDefaults)
        state.update(provider: .codex, with: [codexEvent(input: 40)])

        state.setTokenProvider(.codex)
        state.resetTokenCounter()

        XCTAssertNotNil(userDefaults.object(forKey: "CPUState.tokenResetAt.codex"))
        // Claude was never reset in this flow, so its key stays unset.
        XCTAssertNil(userDefaults.object(forKey: "CPUState.tokenResetAt.claude"))
    }

    func testLegacyResetKeyMigratesIntoClaudeSlotOnce() {
        let userDefaults = makeUserDefaults()
        let legacy = Date(timeIntervalSince1970: 1_650_000_000)
        userDefaults.set(legacy, forKey: "CPUState.tokenResetAt")

        let state = CPUState(userDefaults: userDefaults)

        XCTAssertEqual(state.tokenStores[.claude]?.resetAt, legacy)        // carried into claude store
        XCTAssertEqual(userDefaults.object(forKey: "CPUState.tokenResetAt.claude") as? Date, legacy)
        XCTAssertNil(userDefaults.object(forKey: "CPUState.tokenResetAt"))  // legacy key removed
    }

    func testClaudeOnlyBatchRegressionUnchanged() {
        // With only Claude data, the default combined view must equal pre-refactor Claude figures.
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(with: [event(input: 1_500, output: 500, cacheRead: 300)])

        XCTAssertEqual(state.tokenAggregate.input, 1_500)
        XCTAssertEqual(state.tokenAggregate.output, 500)
        XCTAssertEqual(state.tokenAggregate.reasoning, 0)
        XCTAssertEqual(state.tokenAggregate.usageTotal, 2_000)   // input + output, reasoning 0
    }

    func testSwitchingProviderRerendersWithoutReingest() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.setTokenVisible(true)
        state.setMetricIdentifierStyle(.icons)
        state.update(provider: .claude, with: [event(input: 1_500)])
        state.update(provider: .codex, with: [codexEvent(input: 3_000)])

        state.setTokenProvider(.claude)
        XCTAssertTrue(state.visibleMenuBarTitles.contains("1.5k"))

        state.setTokenProvider(.codex)   // re-renders from already-ingested batches
        XCTAssertTrue(state.visibleMenuBarTitles.contains("3.0k"))
    }

    // MARK: - Estimated cost (Phase 1)

    func testPublishedCostMatchesHandComputedValueForIngestedEvents() {
        let state = CPUState(userDefaults: makeUserDefaults())
        // Opus 4.8: 1M input = $5, 200k output = $5, 500k cacheRead = $0.25.
        state.update(with: [event(input: 1_000_000, output: 200_000, cacheRead: 500_000)])

        XCTAssertEqual(state.tokenCost?.totalUSD ?? -1, 10.25, accuracy: 1e-9)
        XCTAssertEqual(state.tokenCost?.perModelUSD.map { $0.model }, ["claude-opus-4-8"])
        XCTAssertEqual(state.tokenCost?.unpricedTokens, 0)
    }

    func testCostRecomputesOnWindowSwitch() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(with: [
            event(at: Date().addingTimeInterval(-2 * 3_600), input: 1_000_000),   // $5, 2h ago
            event(at: Date(), input: 200_000)                                       // $1, now
        ])

        state.setTokenMenuBarWindow(.lastHour)
        XCTAssertEqual(state.tokenCost?.totalUSD ?? -1, 1, accuracy: 1e-9)

        state.setTokenMenuBarWindow(.last24h)
        XCTAssertEqual(state.tokenCost?.totalUSD ?? -1, 6, accuracy: 1e-9)
    }

    func testCostRecomputesOnScopeSwitch() {
        let state = CPUState(userDefaults: makeUserDefaults())
        // MRU session is s2 (newest event).
        state.update(with: [
            event(at: Date().addingTimeInterval(-120), input: 1_000_000, session: "s1", project: "p1"),
            event(at: Date(), input: 400_000, session: "s2", project: "p2")
        ])

        state.setTokenScope(.session)
        XCTAssertEqual(state.tokenCost?.totalUSD ?? -1, 2, accuracy: 1e-9)   // s2 only: 0.4M × $5

        state.setTokenScope(.global)
        XCTAssertEqual(state.tokenCost?.totalUSD ?? -1, 7, accuracy: 1e-9)
    }

    func testCombinedProviderCostSumsBothProvidersWithAttribution() {
        let state = CPUState(userDefaults: makeUserDefaults())   // default selection: combined
        state.update(provider: .claude, with: [event(input: 1_000_000)])             // $5
        state.update(provider: .codex, with: [codexEvent(input: 1_000_000)])         // $1.25

        XCTAssertEqual(state.tokenCost?.totalUSD ?? -1, 6.25, accuracy: 1e-9)
        XCTAssertEqual(state.tokenCost?.perModelUSD.map { $0.model }, ["claude-opus-4-8", "gpt-5-codex"])

        state.setTokenProvider(.codex)
        XCTAssertEqual(state.tokenCost?.totalUSD ?? -1, 1.25, accuracy: 1e-9)
    }

    func testUnknownModelEventsPropagateUnpricedTokens() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(with: [
            event(input: 1_000_000),
            TokenUsageEvent(
                timestamp: Date(),
                model: "mystery-model-9",
                inputTokens: 300,
                outputTokens: 100,
                cacheReadTokens: 0,
                cacheCreationTokens: 0,
                sessionID: "s1.jsonl",
                projectDir: "p1"
            )
        ])

        XCTAssertEqual(state.tokenCost?.totalUSD ?? -1, 5, accuracy: 1e-9)
        XCTAssertEqual(state.tokenCost?.unpricedTokens, 400)
    }

    func testCostIsNilWithoutEvents() {
        let state = CPUState(userDefaults: makeUserDefaults())

        XCTAssertNil(state.tokenCost)
    }

    func testCostEventSetStaysConsistentWithAggregate() {
        // Rolling-window cost and aggregate must derive from the same events: the
        // filtered set's input sum equals the published aggregate's input.
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(with: [
            event(at: Date().addingTimeInterval(-30), input: 100),
            event(at: Date(), input: 40)
        ])

        let filteredInput = state.tokenFilteredEvents.reduce(0) { $0 + $1.inputTokens }
        XCTAssertEqual(filteredInput, state.tokenAggregate.input)
        XCTAssertNotNil(state.tokenCost)
    }

    func testCombinedMergesPerModelAndPerProviderMRU() throws {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(provider: .claude, with: [event(at: Date().addingTimeInterval(-10), input: 100)])  // claude-opus-4-8
        state.update(provider: .codex, with: [codexEvent(at: Date(), input: 50, model: "gpt-5-codex")])

        let models = try XCTUnwrap(state.tokenActiveModels)
        XCTAssertTrue(models.contains("GPT-5 Codex"))
        XCTAssertTrue(models.contains("Opus 4.8"))

        // Per-provider MRU: project scope resolves each provider's own current project.
        state.setTokenScope(.project)
        XCTAssertEqual(state.tokenAggregate.input, 150)   // claude /p1 + codex /cx, each its own MRU project
    }
}
