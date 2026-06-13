import XCTest
@testable import MacMetricsView

@MainActor
final class MenuBarTitleComposerTests: XCTestCase {

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "MacMetricsViewTests.TitleComposer.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        ud.removePersistentDomain(forName: suiteName)
        return ud
    }

    // MARK: - Badge decision

    func testWarningShownWhenGrantMissing() {
        XCTAssertTrue(MenuBarTitleComposer.showsAccessibilityWarning(isAccessibilityGranted: false))
    }

    func testWarningHiddenWhenGranted() {
        XCTAssertFalse(MenuBarTitleComposer.showsAccessibilityWarning(isAccessibilityGranted: true))
    }

    // MARK: - Badge clears as the published grant state flips
    //
    // The status item itself (NSStatusItem/NSPopover) is verified by launching the
    // app per testing-standards; here the badge *decision* is asserted against the
    // same published `CPUState` flag that drives the title rebuild.

    func testBadgeClearsWhenPublishedGrantFlipsTrue() {
        let auth = FakeAccessibilityAuthorization(isTrusted: false)
        let state = CPUState(userDefaults: makeUserDefaults(), accessibilityAuthorization: auth)
        XCTAssertTrue(MenuBarTitleComposer.showsAccessibilityWarning(isAccessibilityGranted: state.isAccessibilityGranted))

        auth.isTrusted = true
        state.refreshAccessibilityAuthorization()

        XCTAssertFalse(MenuBarTitleComposer.showsAccessibilityWarning(isAccessibilityGranted: state.isAccessibilityGranted))
    }

    // MARK: - Update badge decisions

    func testShowsUpdateBadgeReturnsTrueForVersion() {
        XCTAssertTrue(MenuBarTitleComposer.showsUpdateBadge(availableVersion: "1.9.1"))
    }

    func testShowsUpdateBadgeReturnsFalseForNil() {
        XCTAssertFalse(MenuBarTitleComposer.showsUpdateBadge(availableVersion: nil))
    }

    func testShowsUpdateBadgeReturnsFalseForEmpty() {
        XCTAssertFalse(MenuBarTitleComposer.showsUpdateBadge(availableVersion: ""))
    }

    func testUpdateBadgeSymbolNameConstant() {
        XCTAssertEqual(MenuBarTitleComposer.updateBadgeSymbolName, "arrow.down.circle.fill")
    }

    func testComposerAndBannerPresentationDecisionsAgree() {
        let versions: [String?] = [nil, "", "1.9.1", "2.0.0"]
        for version in versions {
            XCTAssertEqual(
                MenuBarTitleComposer.showsUpdateBadge(availableVersion: version),
                UpdateBannerPresentation.showsBanner(availableVersion: version)
            )
        }
    }

    func testBothAccessibilityWarningAndUpdateBadgeCanApplySimultaneously() {
        XCTAssertTrue(MenuBarTitleComposer.showsAccessibilityWarning(isAccessibilityGranted: false))
        XCTAssertTrue(MenuBarTitleComposer.showsUpdateBadge(availableVersion: "1.9.1"))
    }
}
