import XCTest
@testable import MacMetricsView

final class MetricsTabLayoutTests: XCTestCase {

    // MARK: - MetricTrend.normalized

    func testNormalizedScalesPeakTo100() {
        XCTAssertEqual(MetricTrend.normalized([10, 20, 40]), [25, 50, 100])
    }

    func testNormalizedEmptyStaysEmpty() {
        XCTAssertEqual(MetricTrend.normalized([]), [])
    }

    func testNormalizedAllZeroStaysUnchanged() {
        XCTAssertEqual(MetricTrend.normalized([0, 0, 0]), [0, 0, 0])
    }

    func testNormalizedSingleValueScalesToPeak() {
        XCTAssertEqual(MetricTrend.normalized([42]), [100])
    }

    // MARK: - MetricTrend.ramSeries

    func testRamSeriesUsesUsedTotal() {
        let result = MetricTrend.ramSeries(usedTotal: [5, 6])
        XCTAssertEqual(result, [5, 6])
    }

}
