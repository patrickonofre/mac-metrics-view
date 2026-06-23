import XCTest
@testable import MacMetricsView

@MainActor
final class MenuBarTitleComposerTests: XCTestCase {

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
}
