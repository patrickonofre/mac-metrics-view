import XCTest
@testable import MacMetricsView

/// Direct tests for `TokenUsageModel` extracted from `CPUState` (task-001). They exercise
/// the model standalone (no `CPUState`) and pin the persistence keys so the extraction is
/// proven backward-compatible (same `CPUState.token…` keys, no migration).
@MainActor
final class TokenUsageModelTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "TokenUsageModelTests.\(UUID().uuidString)")!
    }

    private func defaultSelection() -> TokenDisplaySelection {
        TokenDisplaySelection(
            scope: .global,
            window: .today,
            provider: .combined,
            sessionBudget: 0,
            weeklyBudget: 0
        )
    }

    private func event(input: Int, model: String = "claude-opus-4-8") -> TokenUsageEvent {
        TokenUsageEvent(
            timestamp: Date(),
            model: model,
            inputTokens: input,
            outputTokens: 0,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            sessionID: "s1.jsonl",
            projectDir: "p1"
        )
    }

    func testIngestMakesAggregateNonEmpty() {
        let model = TokenUsageModel(userDefaults: makeDefaults(), selection: defaultSelection())
        XCTAssertTrue(model.isEmpty)
        model.update(with: [event(input: 100)])
        XCTAssertFalse(model.isEmpty)
    }

    func testDailyLedgerPersistsAndReloadsUnderLegacyCPUStateKeys() {
        let defaults = makeDefaults()
        let model = TokenUsageModel(userDefaults: defaults, selection: defaultSelection())
        model.update(with: [event(input: 500)])
        XCTAssertGreaterThan(
            model.dailyLedger.weeklyTotal(now: Date(), calendar: .current).usage.total, 0
        )

        // The payload persists under the unchanged CPUState key (no migration).
        XCTAssertNotNil(defaults.data(forKey: "CPUState.tokenDailyLedger.claude"))

        // A fresh model over the same defaults restores the ledger (key round-trip).
        let reloaded = TokenUsageModel(userDefaults: defaults, selection: defaultSelection())
        XCTAssertGreaterThan(
            reloaded.dailyLedger.weeklyTotal(now: Date(), calendar: .current).usage.total, 0
        )
    }

    // MARK: - Ledger persistence debounce (OPT-09)

    /// Counts writes to the ledger key by observing the stored payload identity between calls.
    private func ledgerData(_ ud: UserDefaults) -> Data? {
        ud.data(forKey: "CPUState.tokenDailyLedger.claude")
    }

    func testLedgerWriteIsDebouncedWithinInterval() {
        let defaults = makeDefaults()
        var clock = Date(timeIntervalSince1970: 1_700_000_000)
        let model = TokenUsageModel(
            userDefaults: defaults,
            selection: defaultSelection(),
            ledgerPersistInterval: 30,
            ledgerClock: { clock }
        )

        // First batch: distantPast baseline → writes immediately.
        model.update(with: [event(input: 100)])
        let afterFirst = ledgerData(defaults)
        XCTAssertNotNil(afterFirst)

        // Second batch 5s later (< 30s): no new write — payload unchanged despite new totals.
        clock = clock.addingTimeInterval(5)
        model.update(with: [event(input: 200)])
        XCTAssertEqual(ledgerData(defaults), afterFirst, "within the debounce window the ledger is not re-persisted")

        // A batch past the interval writes again (payload changes with the accumulated totals).
        clock = clock.addingTimeInterval(30)
        model.update(with: [event(input: 300)])
        XCTAssertNotEqual(ledgerData(defaults), afterFirst, "past the debounce window the ledger is persisted")
    }

    func testFlushPersistsPendingLedgerAndIsNoOpWhenClean() {
        let defaults = makeDefaults()
        var clock = Date(timeIntervalSince1970: 1_700_000_000)
        let model = TokenUsageModel(
            userDefaults: defaults,
            selection: defaultSelection(),
            ledgerPersistInterval: 30,
            ledgerClock: { clock }
        )

        model.update(with: [event(input: 100)])                 // writes (baseline)
        let afterFirst = ledgerData(defaults)

        clock = clock.addingTimeInterval(2)
        model.update(with: [event(input: 900)])                 // pending (debounced)
        XCTAssertEqual(ledgerData(defaults), afterFirst)

        model.flushLedgerIfDirty()                              // forces the pending write
        XCTAssertNotEqual(ledgerData(defaults), afterFirst)

        // Flush again with nothing dirty must not throw or change anything.
        let afterFlush = ledgerData(defaults)
        model.flushLedgerIfDirty()
        XCTAssertEqual(ledgerData(defaults), afterFlush)
    }

    func testFlushedLedgerAndWatermarkReloadTogether() {
        let defaults = makeDefaults()
        var clock = Date(timeIntervalSince1970: 1_700_000_000)
        let model = TokenUsageModel(
            userDefaults: defaults,
            selection: defaultSelection(),
            ledgerPersistInterval: 30,
            ledgerClock: { clock }
        )
        model.update(with: [event(input: 100)])
        clock = clock.addingTimeInterval(3)
        model.update(with: [event(input: 250)])   // pending
        model.flushLedgerIfDirty()

        // FR-6: both keys are present after a flush (never one without the other).
        XCTAssertNotNil(defaults.data(forKey: "CPUState.tokenDailyLedger.claude"))
        XCTAssertNotNil(defaults.object(forKey: "CPUState.tokenLedgerWatermark.claude"))

        // Events carry real `Date()` timestamps (the injected clock only paces the debounce),
        // so the weekly window is queried at real now, where the reloaded ledger has data.
        let reloaded = TokenUsageModel(userDefaults: defaults, selection: defaultSelection())
        XCTAssertGreaterThan(
            reloaded.dailyLedger.weeklyTotal(now: Date(), calendar: .current).usage.total, 0
        )
    }

    func testLegacyResetKeyMigratesIntoClaudeSlot() {
        let defaults = makeDefaults()
        let legacy = Date(timeIntervalSince1970: 1_700_000_000)
        defaults.set(legacy, forKey: "CPUState.tokenResetAt")

        _ = TokenUsageModel(userDefaults: defaults, selection: defaultSelection())

        XCTAssertEqual(defaults.object(forKey: "CPUState.tokenResetAt.claude") as? Date, legacy)
        XCTAssertNil(
            defaults.object(forKey: "CPUState.tokenResetAt"),
            "legacy key removed after one-time migration"
        )
    }
}
