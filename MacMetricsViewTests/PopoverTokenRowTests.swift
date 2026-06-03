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
