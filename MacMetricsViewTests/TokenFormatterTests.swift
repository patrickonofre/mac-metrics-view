import XCTest
@testable import MacMetricsView

final class TokenFormatterTests: XCTestCase {

    private func aggregate(
        input: Int = 0,
        output: Int = 0,
        cacheRead: Int = 0,
        cacheCreation: Int = 0
    ) -> TokenAggregate {
        TokenAggregate(input: input, output: output, cacheRead: cacheRead, cacheCreation: cacheCreation)
    }

    // MARK: - Humanization

    func testHumanizedCompactsThousandsAndMillions() {
        XCTAssertEqual(TokenFormatter.humanized(950), "950")
        XCTAssertEqual(TokenFormatter.humanized(1_500), "1.5k")
        XCTAssertEqual(TokenFormatter.humanized(2_300_000), "2.3M")
    }

    func testHumanizedClampsNegativeToZero() {
        XCTAssertEqual(TokenFormatter.humanized(-5), "0")
    }

    // MARK: - Menu bar title

    func testMenuBarTitleWithAndWithoutLabel() {
        let today = aggregate(input: 1_500)   // total 1500

        XCTAssertEqual(TokenFormatter.menuBarTitle(for: today, showLabel: true), "TOK 1.5k")
        XCTAssertEqual(TokenFormatter.menuBarTitle(for: today, showLabel: false), "1.5k")
    }

    func testMenuBarTitleForAbsentDataIsPlaceholderNotZero() {
        XCTAssertEqual(TokenFormatter.menuBarTitle(for: nil, showLabel: false), "--")
    }

    // MARK: - Breakdown

    func testBreakdownRendersInputOutputCache() {
        let agg = aggregate(input: 1_000, output: 2_000, cacheRead: 1_500, cacheCreation: 1_500)

        let rows = TokenFormatter.breakdown(for: agg, language: .english)

        XCTAssertEqual(rows.map(\.label), ["Input", "Output", "Cache"])
        XCTAssertEqual(rows.map(\.value), ["1.0k", "2.0k", "3.0k"])   // cache = read + creation
    }

    // MARK: - Empty state

    func testEmptyStateDetectionAndCopy() {
        XCTAssertTrue(TokenFormatter.isEmpty(nil))
        XCTAssertTrue(TokenFormatter.isEmpty(.zero))
        XCTAssertFalse(TokenFormatter.isEmpty(aggregate(input: 1)))

        let empty = TokenFormatter.emptyState(.english)
        XCTAssertFalse(empty.isEmpty)
        XCTAssertNotEqual(empty, "0")
        XCTAssertEqual(empty, Strings.tokenEmptyState(.english))
    }

    // MARK: - Severity

    func testSeverityIsAlwaysNormal() {
        XCTAssertEqual(TokenFormatter.menuBarTextStyle(for: nil), .normal)
        XCTAssertEqual(TokenFormatter.menuBarTextStyle(for: aggregate(input: 9_999_999)), .normal)
    }
}
