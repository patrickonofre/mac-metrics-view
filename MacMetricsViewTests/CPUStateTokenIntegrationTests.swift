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

        XCTAssertEqual(state.token.aggregate.input, 100)   // default scope global, window today
        XCTAssertEqual(state.token.aggregate.total, 100)
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
        XCTAssertEqual(state.token.aggregate.input, 40)   // s2 only
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
        XCTAssertEqual(state.token.aggregate.input, 10)

        state.setTokenMenuBarWindow(.last24h)
        XCTAssertEqual(state.token.aggregate.input, 60)
    }

    // MARK: - Reset

    func testResetTokenCounterZeroesSinceResetButLeavesRollingWindows() {
        let userDefaults = makeUserDefaults()
        let state = CPUState(userDefaults: userDefaults)
        state.update(with: [event(input: 100)])

        state.setTokenMenuBarWindow(.sinceReset)
        XCTAssertEqual(state.token.aggregate.input, 100)

        state.resetTokenCounter()
        XCTAssertEqual(state.token.aggregate.input, 0)              // since-reset zeroed
        // Default provider is combined → reset persists per-provider keys (both).
        XCTAssertNotNil(userDefaults.object(forKey: "CPUState.tokenResetAt.claude"))
        XCTAssertNotNil(userDefaults.object(forKey: "CPUState.tokenResetAt.codex"))

        state.setTokenMenuBarWindow(.last24h)
        XCTAssertEqual(state.token.aggregate.input, 100)           // rolling window unaffected
    }

    // MARK: - Visibility vs ingestion

    func testIngestionWorksWhileTokenHiddenFromMenuBar() {
        let state = CPUState(userDefaults: makeUserDefaults())
        // showTokens defaults to false.
        state.update(with: [event(input: 100)])

        XCTAssertEqual(state.token.aggregate.input, 100)   // ingested despite being hidden
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

        XCTAssertEqual(state.token.tokenStores[.codex]?.events.count, 1)
        XCTAssertEqual(state.token.tokenStores[.claude]?.events.count, 0)   // claude untouched
    }

    func testCombinedAggregateSumsBothProviders() {
        let state = CPUState(userDefaults: makeUserDefaults())   // default selection: combined
        state.update(provider: .claude, with: [event(input: 100, output: 200)])
        state.update(provider: .codex, with: [codexEvent(input: 10, output: 20, reasoning: 5)])

        XCTAssertEqual(state.tokenProvider, .combined)
        XCTAssertEqual(state.token.aggregate.input, 110)
        XCTAssertEqual(state.token.aggregate.output, 220)
        XCTAssertEqual(state.token.aggregate.reasoning, 5)
        XCTAssertEqual(state.token.aggregate.usageTotal, 110 + 220 + 5)
    }

    func testSetTokenProviderReflectsOnlyThatProvider() {
        let userDefaults = makeUserDefaults()
        let state = CPUState(userDefaults: userDefaults)
        state.update(provider: .claude, with: [event(input: 100)])
        state.update(provider: .codex, with: [codexEvent(input: 10, reasoning: 5)])

        state.setTokenProvider(.codex)
        XCTAssertEqual(state.token.aggregate.input, 10)
        XCTAssertEqual(state.token.aggregate.reasoning, 5)
        XCTAssertEqual(MetricDisplaySettings.load(from: userDefaults).tokenProvider, .codex)

        state.setTokenProvider(.claude)
        XCTAssertEqual(state.token.aggregate.input, 100)
        XCTAssertEqual(state.token.aggregate.reasoning, 0)
    }

    func testResetScopedToSelectedProvider() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(provider: .claude, with: [event(input: 100)])
        state.update(provider: .codex, with: [codexEvent(input: 40)])
        state.setTokenMenuBarWindow(.sinceReset)

        // Reset only Codex.
        state.setTokenProvider(.codex)
        state.resetTokenCounter()
        XCTAssertEqual(state.token.aggregate.input, 0)              // codex since-reset zeroed
        state.setTokenProvider(.claude)
        XCTAssertEqual(state.token.aggregate.input, 100)            // claude untouched

        // Reset both via combined.
        state.setTokenProvider(.combined)
        state.resetTokenCounter()
        XCTAssertEqual(state.token.aggregate.input, 0)
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

        XCTAssertEqual(state.token.tokenStores[.claude]?.resetAt, legacy)        // carried into claude store
        XCTAssertEqual(userDefaults.object(forKey: "CPUState.tokenResetAt.claude") as? Date, legacy)
        XCTAssertNil(userDefaults.object(forKey: "CPUState.tokenResetAt"))  // legacy key removed
    }

    func testClaudeOnlyBatchRegressionUnchanged() {
        // With only Claude data, the default combined view must equal pre-refactor Claude figures.
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(with: [event(input: 1_500, output: 500, cacheRead: 300)])

        XCTAssertEqual(state.token.aggregate.input, 1_500)
        XCTAssertEqual(state.token.aggregate.output, 500)
        XCTAssertEqual(state.token.aggregate.reasoning, 0)
        XCTAssertEqual(state.token.aggregate.usageTotal, 2_000)   // input + output, reasoning 0
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

        XCTAssertEqual(state.token.cost?.totalUSD ?? -1, 10.25, accuracy: 1e-9)
        XCTAssertEqual(state.token.cost?.perModelUSD.map { $0.model }, ["claude-opus-4-8"])
        XCTAssertEqual(state.token.cost?.unpricedTokens, 0)
    }

    func testCostRecomputesOnWindowSwitch() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(with: [
            event(at: Date().addingTimeInterval(-2 * 3_600), input: 1_000_000),   // $5, 2h ago
            event(at: Date(), input: 200_000)                                       // $1, now
        ])

        state.setTokenMenuBarWindow(.lastHour)
        XCTAssertEqual(state.token.cost?.totalUSD ?? -1, 1, accuracy: 1e-9)

        state.setTokenMenuBarWindow(.last24h)
        XCTAssertEqual(state.token.cost?.totalUSD ?? -1, 6, accuracy: 1e-9)
    }

    func testCostRecomputesOnScopeSwitch() {
        let state = CPUState(userDefaults: makeUserDefaults())
        // MRU session is s2 (newest event).
        state.update(with: [
            event(at: Date().addingTimeInterval(-120), input: 1_000_000, session: "s1", project: "p1"),
            event(at: Date(), input: 400_000, session: "s2", project: "p2")
        ])

        state.setTokenScope(.session)
        XCTAssertEqual(state.token.cost?.totalUSD ?? -1, 2, accuracy: 1e-9)   // s2 only: 0.4M × $5

        state.setTokenScope(.global)
        XCTAssertEqual(state.token.cost?.totalUSD ?? -1, 7, accuracy: 1e-9)
    }

    func testCombinedProviderCostSumsBothProvidersWithAttribution() {
        let state = CPUState(userDefaults: makeUserDefaults())   // default selection: combined
        state.update(provider: .claude, with: [event(input: 1_000_000)])             // $5
        state.update(provider: .codex, with: [codexEvent(input: 1_000_000)])         // $1.25

        XCTAssertEqual(state.token.cost?.totalUSD ?? -1, 6.25, accuracy: 1e-9)
        XCTAssertEqual(state.token.cost?.perModelUSD.map { $0.model }, ["claude-opus-4-8", "gpt-5-codex"])

        state.setTokenProvider(.codex)
        XCTAssertEqual(state.token.cost?.totalUSD ?? -1, 1.25, accuracy: 1e-9)
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

        XCTAssertEqual(state.token.cost?.totalUSD ?? -1, 5, accuracy: 1e-9)
        XCTAssertEqual(state.token.cost?.unpricedTokens, 400)
    }

    func testCostIsNilWithoutEvents() {
        let state = CPUState(userDefaults: makeUserDefaults())

        XCTAssertNil(state.token.cost)
    }

    func testCostEventSetStaysConsistentWithAggregate() {
        // Rolling-window cost and aggregate must derive from the same events: the
        // filtered set's input sum equals the published aggregate's input.
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(with: [
            event(at: Date().addingTimeInterval(-30), input: 100),
            event(at: Date(), input: 40)
        ])

        let filteredInput = state.token.filteredEvents.reduce(0) { $0 + $1.inputTokens }
        XCTAssertEqual(filteredInput, state.token.aggregate.input)
        XCTAssertNotNil(state.token.cost)
    }

    // MARK: - Burn rate (Phase 2, task_04)

    func testBurnRateMatchesHandComputedValueForRecentEvents() throws {
        let state = CPUState(userDefaults: makeUserDefaults())
        // 10 minutes old, inside the trailing hour. Opus 4.8: 1M input = $5.
        state.update(with: [event(at: Date().addingTimeInterval(-600), input: 1_000_000, output: 200_000)])

        let rate = try XCTUnwrap(state.token.burnRate)
        XCTAssertEqual(rate.tokensPerHour, 1_200_000, accuracy: 1e-6)
        XCTAssertEqual(rate.costPerHourUSD, 10, accuracy: 1e-9)   // $5 input + $5 output (200k × $25)
        XCTAssertEqual(rate.costPerDayUSD, rate.costPerHourUSD * 24, accuracy: 1e-9)
    }

    func testBurnRateIgnoresWindowPickerSwitch() throws {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(with: [event(at: Date().addingTimeInterval(-600), input: 500_000)])

        let before = try XCTUnwrap(state.token.burnRate)
        state.setTokenMenuBarWindow(.last24h)
        let after = try XCTUnwrap(state.token.burnRate)

        XCTAssertEqual(before.tokensPerHour, after.tokensPerHour, accuracy: 1)
        XCTAssertEqual(before.costPerHourUSD, after.costPerHourUSD, accuracy: 1e-6)
    }

    func testBurnRateIgnoresScopePickerSwitch() throws {
        let state = CPUState(userDefaults: makeUserDefaults())
        // Two sessions; session scope narrows the counter to MRU s2, but the rate
        // keeps counting both (timestamp-only filter, ADR-004).
        state.update(with: [
            event(at: Date().addingTimeInterval(-120), input: 100_000, session: "s1", project: "p1"),
            event(at: Date(), input: 40_000, session: "s2", project: "p2")
        ])

        let before = try XCTUnwrap(state.token.burnRate)
        state.setTokenScope(.session)
        let after = try XCTUnwrap(state.token.burnRate)

        XCTAssertEqual(state.token.aggregate.input, 40_000)        // counter narrowed
        XCTAssertEqual(after.tokensPerHour, 140_000, accuracy: 1)  // rate did not
        XCTAssertEqual(before.tokensPerHour, after.tokensPerHour, accuracy: 1)
    }

    func testBurnRateFollowsProviderSelection() throws {
        let state = CPUState(userDefaults: makeUserDefaults())   // default: combined
        state.update(provider: .claude, with: [event(at: Date().addingTimeInterval(-60), input: 100_000)])
        state.update(provider: .codex, with: [codexEvent(at: Date().addingTimeInterval(-30), input: 50_000, reasoning: 10_000)])

        let combined = try XCTUnwrap(state.token.burnRate)
        XCTAssertEqual(combined.tokensPerHour, 160_000, accuracy: 1)

        state.setTokenProvider(.codex)
        let codexOnly = try XCTUnwrap(state.token.burnRate)
        XCTAssertEqual(codexOnly.tokensPerHour, 60_000, accuracy: 1)   // Claude contribution dropped
    }

    func testBurnRateNilWhenEventsOlderThanHourButCounterStillShowsThem() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(with: [event(at: Date().addingTimeInterval(-2 * 3_600), input: 100)])   // 2h ago

        state.setTokenMenuBarWindow(.last24h)
        XCTAssertEqual(state.token.aggregate.input, 100)   // 24h counter sees it
        XCTAssertNil(state.token.burnRate)                  // trailing hour does not
    }

    func testBurnRateNilWithNoEvents() {
        let state = CPUState(userDefaults: makeUserDefaults())

        XCTAssertNil(state.token.burnRate)
    }

    func testPublishedBurnRateConsistentWithDirectCompute() throws {
        // Full path: store append → recompute → published rate equals compute() over
        // the same merged store events with a now in the same pass-window.
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(with: [
            event(at: Date().addingTimeInterval(-300), input: 250_000),
            event(at: Date().addingTimeInterval(-30), input: 50_000, output: 10_000)
        ])

        let published = try XCTUnwrap(state.token.burnRate)
        let events = state.token.tokenStores[.claude]!.events + state.token.tokenStores[.codex]!.events
        let direct = try XCTUnwrap(TokenBurnRate.compute(events: events, now: Date()))

        XCTAssertEqual(published.tokensPerHour, direct.tokensPerHour, accuracy: 1)
        XCTAssertEqual(published.costPerHourUSD, direct.costPerHourUSD, accuracy: 1e-6)
        XCTAssertEqual(published.costPerDayUSD, direct.costPerDayUSD, accuracy: 1e-4)
    }

    // MARK: - Popover-scoped auto-refresh (Phase 2, task_05)

    func testBeginTokenAutoRefreshRecomputesImmediately() throws {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(with: [event(at: Date().addingTimeInterval(-600), input: 120_000)])

        state.beginTokenAutoRefresh()
        defer { state.endTokenAutoRefresh() }

        let rate = try XCTUnwrap(state.token.burnRate)
        XCTAssertEqual(rate.tokensPerHour, 120_000, accuracy: 1)
    }

    func testTickWithAdvancedNowClearsBurnRateWhileLast24hCounterKeepsEvent() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.setTokenMenuBarWindow(.last24h)
        state.update(with: [event(input: 100)])
        XCTAssertNotNil(state.token.burnRate)

        state.beginTokenAutoRefresh()
        defer { state.endTokenAutoRefresh() }
        state.tokenAutoRefreshTick(now: Date().addingTimeInterval(61 * 60))   // window slid past it

        XCTAssertNil(state.token.burnRate)
        XCTAssertEqual(state.token.aggregate.input, 100)   // 24h counter still shows it
    }

    func testTickThirtyMinutesLaterKeepsRateUnchangedFixedDenominator() throws {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(with: [event(input: 120_000)])
        let before = try XCTUnwrap(state.token.burnRate)

        state.beginTokenAutoRefresh()
        defer { state.endTokenAutoRefresh() }
        state.tokenAutoRefreshTick(now: Date().addingTimeInterval(30 * 60))   // still in-window

        let after = try XCTUnwrap(state.token.burnRate)
        XCTAssertEqual(before.tokensPerHour, after.tokensPerHour, accuracy: 1)
    }

    func testDoubleBeginThenSingleEndLeavesNoLiveTick() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(with: [event(input: 100)])

        state.beginTokenAutoRefresh()
        state.beginTokenAutoRefresh()   // must not stack a second timer
        state.endTokenAutoRefresh()

        // With no live timer, a time-advanced tick is a no-op: the rate would have
        // cleared if a recompute had run with the advanced clock.
        state.tokenAutoRefreshTick(now: Date().addingTimeInterval(61 * 60))
        XCTAssertNotNil(state.token.burnRate)
    }

    func testEndWithoutBeginIsANoOp() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(with: [event(input: 100)])

        state.endTokenAutoRefresh()   // must not crash or change published state

        XCTAssertNotNil(state.token.burnRate)
        XCTAssertEqual(state.token.aggregate.input, 100)
    }

    func testTickRefreshesLastHourAggregateSoAgedOutEventLeavesCounterToo() {
        // ADR-005 side benefit: rolling windows stay honest while the popover is open.
        let state = CPUState(userDefaults: makeUserDefaults())
        state.setTokenMenuBarWindow(.lastHour)
        state.update(with: [event(input: 100)])
        XCTAssertEqual(state.token.aggregate.input, 100)

        state.beginTokenAutoRefresh()
        defer { state.endTokenAutoRefresh() }
        state.tokenAutoRefreshTick(now: Date().addingTimeInterval(61 * 60))

        XCTAssertEqual(state.token.aggregate.input, 0)   // aged out of the lastHour window
    }

    func testReopenAfterCloseReArmsAutoRefreshAndRecomputes() {
        // The popover hosting controller is torn down on close and rebuilt on open (ADR-001);
        // each reopen re-runs PopoverView.onAppear -> beginTokenAutoRefresh. Lock that begin
        // re-arms the timer after a prior end, so a reopened popover keeps sliding its windows.
        // Distinct from testDoubleBeginThenSingleEndLeavesNoLiveTick (which asserts NO
        // recompute after end): here a fresh begin following an end must RESUME ticking.
        let state = CPUState(userDefaults: makeUserDefaults())
        state.setTokenMenuBarWindow(.lastHour)
        state.update(with: [event(input: 100)])

        // First open then close.
        state.beginTokenAutoRefresh()
        state.endTokenAutoRefresh()

        // Reopen: begin must re-arm so an in-flight tick recomputes again. Advancing past the
        // lastHour window ages the event out only if a live timer drove the recompute.
        state.beginTokenAutoRefresh()
        defer { state.endTokenAutoRefresh() }
        state.tokenAutoRefreshTick(now: Date().addingTimeInterval(61 * 60))

        XCTAssertEqual(state.token.aggregate.input, 0)   // recompute ran on the re-armed timer
    }

    func testCombinedMergesPerModelAndPerProviderMRU() throws {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(provider: .claude, with: [event(at: Date().addingTimeInterval(-10), input: 100)])  // claude-opus-4-8
        state.update(provider: .codex, with: [codexEvent(at: Date(), input: 50, model: "gpt-5-codex")])

        let models = try XCTUnwrap(state.token.activeModels)
        XCTAssertTrue(models.contains("GPT-5 Codex"))
        XCTAssertTrue(models.contains("Opus 4.8"))

        // Per-provider MRU: project scope resolves each provider's own current project.
        state.setTokenScope(.project)
        XCTAssertEqual(state.token.aggregate.input, 150)   // claude /p1 + codex /cx, each its own MRU project
    }

    // MARK: - Daily ledger persistence + ingest fold (Phase 3, task_05)

    func testClaudeIngestAccumulatesTodayBucketWithIngestTimeCost() {
        let state = CPUState(userDefaults: makeUserDefaults())
        // Opus 4.8: 1M input = $5; 200k output = $5.
        state.update(with: [
            event(at: Date().addingTimeInterval(-120), input: 1_000_000),
            event(at: Date().addingTimeInterval(-60), output: 200_000)
        ])

        let weekly = state.token.dailyLedger.weeklyTotal(now: Date(), calendar: .current)
        XCTAssertEqual(weekly.usage.input, 1_000_000)
        XCTAssertEqual(weekly.usage.output, 200_000)
        XCTAssertEqual(weekly.costUSD, 10, accuracy: 1e-9)
    }

    func testCodexIngestLeavesLedgerUntouched() {
        let state = CPUState(userDefaults: makeUserDefaults())

        state.update(provider: .codex, with: [codexEvent(input: 500_000)])

        XCTAssertTrue(state.token.dailyLedger.days.isEmpty)
    }

    func testLedgerSurvivesRestartWithIdenticalContents() {
        let userDefaults = makeUserDefaults()
        let state = CPUState(userDefaults: userDefaults)
        state.update(with: [event(at: Date().addingTimeInterval(-60), input: 250_000, output: 10_000)])
        let before = state.token.dailyLedger

        let restarted = CPUState(userDefaults: userDefaults)

        XCTAssertEqual(restarted.token.dailyLedger, before)
        XCTAssertFalse(before.days.isEmpty)
    }

    func testRestartTailReEmissionDoesNotDoubleCountLedger() {
        // The reader's cold-start backfill re-emits the retained tail after a
        // relaunch; the persisted watermark must keep those events out of the
        // ledger (ADR-007 no-double-count rule at the persistence boundary).
        let userDefaults = makeUserDefaults()
        let batch = [
            event(at: Date().addingTimeInterval(-300), input: 100_000),
            event(at: Date().addingTimeInterval(-60), input: 40_000)
        ]
        let state = CPUState(userDefaults: userDefaults)
        state.update(with: batch)
        let weeklyBefore = state.token.dailyLedger.weeklyTotal(now: Date(), calendar: .current)

        let restarted = CPUState(userDefaults: userDefaults)
        restarted.update(with: batch)   // simulated tail re-emission

        let weeklyAfter = restarted.token.dailyLedger.weeklyTotal(now: Date(), calendar: .current)
        XCTAssertEqual(weeklyAfter.usage, weeklyBefore.usage)
        XCTAssertEqual(weeklyAfter.costUSD, weeklyBefore.costUSD, accuracy: 1e-9)
    }

    func testCorruptLedgerPayloadDegradesToEmptyWithoutCrash() {
        let userDefaults = makeUserDefaults()
        userDefaults.set("not json at all".data(using: .utf8)!, forKey: "CPUState.tokenDailyLedger.claude")

        let state = CPUState(userDefaults: userDefaults)

        XCTAssertTrue(state.token.dailyLedger.days.isEmpty)
    }

    func testLedgerPruneAtIngestKeepsTodayPlusSevenDays() {
        let state = CPUState(userDefaults: makeUserDefaults())
        // 9 synthetic days, oldest first so the watermark never skips a fold.
        for daysBack in stride(from: 8, through: 0, by: -1) {
            state.update(with: [event(at: Date().addingTimeInterval(Double(-daysBack) * 86_400), input: 10)])
        }

        XCTAssertEqual(state.token.dailyLedger.days.count, 8)   // today + 7, the 8-days-back bucket dropped
    }

    // MARK: - tokenRateLimit snapshot (Phase 3, task_06)

    func testSnapshotMatchesHandComputedBlockWeeklyAndBudgets() throws {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.setTokenSessionBudget(2_000_000)
        state.setTokenWeeklyBudget(10_000_000)
        // One Claude event 10 min ago: in the active block and today's bucket.
        state.update(with: [event(at: Date().addingTimeInterval(-600), input: 1_000_000, output: 200_000)])

        let snapshot = try XCTUnwrap(state.token.rateLimit)
        let block = try XCTUnwrap(snapshot.block)
        XCTAssertEqual(block.usage.input, 1_000_000)
        XCTAssertEqual(block.usage.output, 200_000)
        XCTAssertEqual(block.costUSD, 10, accuracy: 1e-9)        // $5 input + $5 output
        XCTAssertEqual(block.end, block.start.addingTimeInterval(5 * 3_600))
        XCTAssertEqual(snapshot.weeklyUsage.input, 1_000_000)
        XCTAssertEqual(snapshot.weeklyCostUSD, 10, accuracy: 1e-9)
        XCTAssertEqual(snapshot.sessionBudget, 2_000_000)
        XCTAssertEqual(snapshot.weeklyBudget, 10_000_000)
    }

    func testSnapshotIgnoresProviderScopeAndWindowPickers() throws {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(provider: .claude, with: [event(at: Date().addingTimeInterval(-300), input: 100_000)])
        state.update(provider: .codex, with: [codexEvent(at: Date().addingTimeInterval(-60), input: 999_000)])
        let before = try XCTUnwrap(state.token.rateLimit)

        state.setTokenProvider(.codex)   // Codex-only selection
        state.setTokenScope(.session)
        state.setTokenMenuBarWindow(.lastHour)

        let after = try XCTUnwrap(state.token.rateLimit)
        XCTAssertEqual(after, before)                              // Claude-scoped, picker-independent
        XCTAssertEqual(after.block?.usage.input, 100_000)          // Codex event never counted
    }

    func testTickPastBlockEndClearsBlockButKeepsWeeklyFigure() throws {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(with: [event(at: Date().addingTimeInterval(-60), input: 50_000)])
        XCTAssertNotNil(try XCTUnwrap(state.token.rateLimit).block)

        state.beginTokenAutoRefresh()
        defer { state.endTokenAutoRefresh() }
        state.tokenAutoRefreshTick(now: Date().addingTimeInterval(6 * 3_600))   // past block end

        let snapshot = try XCTUnwrap(state.token.rateLimit)        // still published
        XCTAssertNil(snapshot.block)                               // block expired
        XCTAssertEqual(snapshot.weeklyUsage.input, 50_000)         // week persists
    }

    func testSnapshotNilWithEmptyStoreAndEmptyLedger() {
        let state = CPUState(userDefaults: makeUserDefaults())

        XCTAssertNil(state.token.rateLimit)
    }

    func testBudgetSettersPersistSanitizeAndRepublish() throws {
        let userDefaults = makeUserDefaults()
        let state = CPUState(userDefaults: userDefaults)
        state.update(with: [event(at: Date().addingTimeInterval(-60), input: 1_000)])

        state.setTokenSessionBudget(2_000_000)
        state.setTokenWeeklyBudget(-5)   // sanitized to 0

        let snapshot = try XCTUnwrap(state.token.rateLimit)
        XCTAssertEqual(snapshot.sessionBudget, 2_000_000)
        XCTAssertEqual(snapshot.weeklyBudget, 0)
        let persisted = MetricDisplaySettings.load(from: userDefaults)
        XCTAssertEqual(persisted.tokenSessionBudget, 2_000_000)
        XCTAssertEqual(persisted.tokenWeeklyBudget, 0)
    }

    func testIngestRecomputeUpdatesBlockAndTodayContributionInOnePass() throws {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.update(with: [event(at: Date().addingTimeInterval(-1_200), input: 100_000)])
        let first = try XCTUnwrap(state.token.rateLimit)

        state.update(with: [event(at: Date().addingTimeInterval(-30), input: 40_000)])

        let second = try XCTUnwrap(state.token.rateLimit)
        XCTAssertEqual(second.block?.usage.input, 140_000)
        XCTAssertEqual(second.weeklyUsage.input, 140_000)
        XCTAssertGreaterThan(second.weeklyUsage.input, first.weeklyUsage.input)
    }

    func testBatchPersistenceReflectsAllEventsOfTheBatch() {
        let userDefaults = makeUserDefaults()
        let state = CPUState(userDefaults: userDefaults)
        let batch = (1...5).map { event(at: Date().addingTimeInterval(Double(-$0)), input: 10_000) }

        state.update(with: batch)

        // Full path: ingest → persisted payload → reload → weekly sum sees all N.
        let reloaded = CPUState(userDefaults: userDefaults)
        let weekly = reloaded.token.dailyLedger.weeklyTotal(now: Date(), calendar: .current)
        XCTAssertEqual(weekly.usage.input, 50_000)
        XCTAssertEqual(weekly.costUSD, 0.25, accuracy: 1e-9)   // 50k × $5/MTok
    }

}
