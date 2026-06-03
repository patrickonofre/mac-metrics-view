import XCTest
@testable import MacMetricsView

/// Verifies the token menu-bar segment *decisions* (presence, count text, label-vs-icon,
/// styling) against the published `CPUState` surfaces that drive the title rebuild. The
/// rendered glyph/attributed string in `StatusItemController` is verified by launching the
/// app, per the project's testing standards (see MenuBarTitleComposerTests).
@MainActor
final class StatusItemTokenSegmentTests: XCTestCase {
    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "MacMetricsViewTests.TokenSegment.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        ud.removePersistentDomain(forName: suiteName)
        return ud
    }

    private func event(at date: Date = Date(), input: Int) -> TokenUsageEvent {
        TokenUsageEvent(
            timestamp: date,
            model: "claude-opus-4-8",
            inputTokens: input,
            outputTokens: 0,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            sessionID: "s1.jsonl",
            projectDir: "p1"
        )
    }

    func testTokenSegmentShowsHumanizedCountWhenVisible() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.setTokenVisible(true)
        state.update(with: [event(input: 12_300)])

        XCTAssertTrue(state.visibleMenuBarTitles.contains("12.3k"))
    }

    func testNoTokenSegmentWhenHidden() {
        let state = CPUState(userDefaults: makeUserDefaults())
        // showTokens defaults to false.
        state.update(with: [event(input: 12_300)])

        XCTAssertFalse(state.visibleMenuBarTitles.contains { $0.contains("12.3k") })
    }

    func testLabelsStyleShowsLabelIconsStyleOmitsTextLabel() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.setTokenVisible(true)
        state.update(with: [event(input: 12_300)])

        state.setMetricIdentifierStyle(.labels)
        XCTAssertTrue(state.visibleMenuBarTitles.contains("\(TokenFormatter.menuBarLabel) 12.3k"))

        state.setMetricIdentifierStyle(.icons)
        // In icons mode the plain title carries only the count; the SF Symbol is rendered
        // separately by StatusItemController, so no text label appears here.
        XCTAssertTrue(state.visibleMenuBarTitles.contains("12.3k"))
        XCTAssertFalse(state.visibleMenuBarTitles.contains { $0.contains(TokenFormatter.menuBarLabel) })
    }

    func testTokenStyleIsNormalRegardlessOfMagnitude() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.setTokenVisible(true)
        state.update(with: [event(input: 9_999_999)])

        XCTAssertEqual(state.tokenMenuBarTextStyle, .normal)
    }

    // MARK: - Integration

    func testChangingWindowUpdatesTokenSegmentCount() {
        let state = CPUState(userDefaults: makeUserDefaults())
        state.setTokenVisible(true)
        state.update(with: [
            event(at: Date().addingTimeInterval(-2 * 3_600), input: 50_000),  // 2h ago
            event(at: Date(), input: 1_500)                                    // now
        ])

        state.setTokenMenuBarWindow(.lastHour)
        XCTAssertTrue(state.visibleMenuBarTitles.contains("1.5k"))

        state.setTokenMenuBarWindow(.last24h)
        XCTAssertTrue(state.visibleMenuBarTitles.contains("51.5k"))
    }
}
