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

    func testRamSeriesSelectsPressure() {
        let result = MetricTrend.ramSeries(metric: .pressure, pressure: [1, 2], appMemory: [9, 8], usedTotal: [5, 6])
        XCTAssertEqual(result, [1, 2])
    }

    func testRamSeriesSelectsAppMemory() {
        let result = MetricTrend.ramSeries(metric: .appMemory, pressure: [1, 2], appMemory: [9, 8], usedTotal: [5, 6])
        XCTAssertEqual(result, [9, 8])
    }

    func testRamSeriesSelectsUsedTotal() {
        let result = MetricTrend.ramSeries(metric: .usedTotal, pressure: [1, 2], appMemory: [9, 8], usedTotal: [5, 6])
        XCTAssertEqual(result, [5, 6])
    }

    // MARK: - MetricGridLayout.rows

    func testRowsAllCollapsedPairsTwoPerRow() {
        let rows = MetricGridLayout.rows(order: PopoverTabPresentation.cardOrder, expanded: [])
        // 7 cards -> [cpu,gpu][ram,network][temperature,disk][battery]
        XCTAssertEqual(rows, [
            [.cpu, .gpu],
            [.ram, .network],
            [.temperature, .disk],
            [.battery]
        ])
    }

    func testExpandedCardTakesOwnFullWidthRow() {
        let rows = MetricGridLayout.rows(order: PopoverTabPresentation.cardOrder, expanded: [.battery])
        XCTAssertEqual(rows.last, [.battery])
    }

    func testExpandedCardFlushesPendingPartnerToSingleRow() {
        // temperature is the pending partner of disk; expanding disk splits the pair.
        let rows = MetricGridLayout.rows(order: PopoverTabPresentation.cardOrder, expanded: [.disk])
        XCTAssertTrue(rows.contains([.temperature]))
        XCTAssertTrue(rows.contains([.disk]))
        XCTAssertFalse(rows.contains([.temperature, .disk]))
    }

    func testEveryCardAppearsExactlyOnce() {
        let rows = MetricGridLayout.rows(order: PopoverTabPresentation.cardOrder, expanded: [.battery])
        let flat = rows.flatMap { $0 }
        XCTAssertEqual(Set(flat), Set(PopoverTabPresentation.cardOrder))
        XCTAssertEqual(flat.count, PopoverTabPresentation.cardOrder.count)
    }
}
