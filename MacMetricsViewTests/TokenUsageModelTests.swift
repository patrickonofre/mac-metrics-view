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
