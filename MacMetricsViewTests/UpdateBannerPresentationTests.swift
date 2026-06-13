import XCTest
@testable import MacMetricsView

final class UpdateBannerPresentationTests: XCTestCase {

    // MARK: - Banner Visibility Decisions

    func testShowsBannerReturnsTrueForNonEmptyVersion() {
        XCTAssertTrue(UpdateBannerPresentation.showsBanner(availableVersion: "1.9.1"))
    }

    func testShowsBannerReturnsFalseForNil() {
        XCTAssertFalse(UpdateBannerPresentation.showsBanner(availableVersion: nil))
    }

    func testShowsBannerReturnsFalseForEmptyString() {
        XCTAssertFalse(UpdateBannerPresentation.showsBanner(availableVersion: ""))
    }

    // MARK: - Localized Title Decisions

    func testTitleForPortugueseEqualsNovaVersaoDisponivel() {
        XCTAssertEqual(
            UpdateBannerPresentation.title(for: "1.9.1", .portuguese),
            "Nova versão 1.9.1 disponível"
        )
    }

    func testTitleForEnglishEqualsNewVersionAvailable() {
        XCTAssertEqual(
            UpdateBannerPresentation.title(for: "1.9.1", .english),
            "New version 1.9.1 available"
        )
    }

    // MARK: - Localized CTA Decisions

    func testUpdateNowCTAResolvesCorrectly() {
        XCTAssertEqual(Strings.updateNow(.english), "Update now")
        XCTAssertEqual(Strings.updateNow(.portuguese), "Atualizar agora")
    }

    // MARK: - Integration Tests for Localization Keys

    func testUpdateNowHasNonEmptyStringsInBothLanguages() {
        XCTAssertFalse(Strings.updateNow(.english).isEmpty)
        XCTAssertFalse(Strings.updateNow(.portuguese).isEmpty)
    }

    func testWhatsNewCTAResolvesCorrectly() {
        XCTAssertEqual(Strings.whatsNew(.english), "What's new")
        XCTAssertEqual(Strings.whatsNew(.portuguese), "Novidades")
    }

    func testWhatsNewHasNonEmptyStringsInBothLanguages() {
        XCTAssertFalse(Strings.whatsNew(.english).isEmpty)
        XCTAssertFalse(Strings.whatsNew(.portuguese).isEmpty)
    }

    func testReleaseNotesURLResolver() {
        let url = UpdateBannerPresentation.releaseNotesURL(for: "1.9.1")
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.absoluteString, "https://github.com/patrickonofre/mac-metrics-view/releases/tag/v1.9.1")
    }
}
