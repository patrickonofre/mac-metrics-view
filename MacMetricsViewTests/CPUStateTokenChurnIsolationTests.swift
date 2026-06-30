import XCTest
import Combine
@testable import MacMetricsView

/// Proves the task-002 churn-isolation contract (spec-cpustate-pillar-decouple): mutating
/// `TokenUsageModel` must not invalidate `CPUState`'s own `objectWillChange` — that bridge
/// was deliberately removed (see the comment on `CPUState.token`) because the menu bar
/// learns about token changes imperatively (`AppDelegate` → `setNeedsTitleUpdate()`), not
/// through Combine, and bridging would re-render every `CPUState` observer (Settings/Actions
/// tabs) on the popover-open 30s auto-refresh tick (ADR-005).
@MainActor
final class CPUStateTokenChurnIsolationTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "CPUStateTokenChurnIsolationTests.\(UUID().uuidString)")!
    }

    private func event(input: Int) -> TokenUsageEvent {
        TokenUsageEvent(
            timestamp: Date(),
            model: "claude-opus-4-8",
            inputTokens: input,
            outputTokens: 0,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            sessionID: "s1.jsonl",
            projectDir: "p1"
        )
    }

    func testTokenIngestDoesNotEmitCPUStateObjectWillChange() {
        let state = CPUState(userDefaults: makeDefaults())
        var fired = false
        let cancellable = state.objectWillChange.sink { fired = true }

        state.update(with: [event(input: 100)])

        XCTAssertFalse(
            fired,
            "token ingest must invalidate only TokenUsageModel, not the CPUState coordinator"
        )
        cancellable.cancel()
    }

    func testTokenAutoRefreshTickDoesNotEmitCPUStateObjectWillChange() {
        let state = CPUState(userDefaults: makeDefaults())
        state.update(with: [event(input: 100)])
        var fired = false
        let cancellable = state.objectWillChange.sink { fired = true }

        state.tokenAutoRefreshTick(now: Date().addingTimeInterval(30))

        XCTAssertFalse(
            fired,
            "the ADR-005 popover-open refresh tick must not ripple to non-token observers"
        )
        cancellable.cancel()
    }

    func testTokenModelObjectWillChangeFiresOnIngest() {
        let state = CPUState(userDefaults: makeDefaults())
        var fired = false
        let cancellable = state.token.objectWillChange.sink { fired = true }

        state.update(with: [event(input: 100)])

        XCTAssertTrue(fired, "TokenUsageModel must still publish its own changes")
        cancellable.cancel()
    }

    func testMenuBarTitleComposesTokenSegmentFromTheExtractedModel() {
        let defaults = makeDefaults()
        let state = CPUState(userDefaults: defaults)
        state.metrics.setTokenVisible(true)

        // Before any ingest: the token segment reflects the model's zero aggregate.
        XCTAssertTrue(
            state.visibleMenuBarTitles.contains(
                TokenFormatter.menuBarTitle(for: state.token.aggregate, showLabel: false)
            )
        )

        state.update(with: [event(input: 1_000_000)])

        // After ingest: the composed title tracks the model's updated aggregate — proving
        // the coordinator reads through `token`, not a stale shim snapshot.
        XCTAssertTrue(
            state.visibleMenuBarTitles.contains(
                TokenFormatter.menuBarTitle(for: state.token.aggregate, showLabel: false)
            )
        )
        XCTAssertTrue(state.accessibilityMenuBarTitle.contains(Strings.tokens()))
    }
}
