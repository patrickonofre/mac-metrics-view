import XCTest
@testable import MacMetricsView

final class TrafficSessionTotalsTests: XCTestCase {
    func testStartsAtZero() {
        let totals = TrafficSessionTotals()
        XCTAssertEqual(totals.inbound, 0)
        XCTAssertEqual(totals.outbound, 0)
    }

    func testAddFoldsRateOverElapsedAsByteDelta() {
        var totals = TrafficSessionTotals()
        // rate × elapsed recovers the exact byte delta the calculator started from.
        totals.add(inboundRate: 1_000, outboundRate: 200, elapsed: 2)
        totals.add(inboundRate: 3_000, outboundRate: 100, elapsed: 1)

        XCTAssertEqual(totals.inbound, 1_000 * 2 + 3_000 * 1)
        XCTAssertEqual(totals.outbound, 200 * 2 + 100 * 1)
    }

    func testIgnoresNonPositiveOrNonFiniteElapsed() {
        var totals = TrafficSessionTotals()
        totals.add(inboundRate: 1_000, outboundRate: 1_000, elapsed: 0)
        totals.add(inboundRate: 1_000, outboundRate: 1_000, elapsed: -5)
        totals.add(inboundRate: 1_000, outboundRate: 1_000, elapsed: .infinity)

        XCTAssertEqual(totals.inbound, 0)
        XCTAssertEqual(totals.outbound, 0)
    }

    func testIgnoresNegativeOrNaNRatesPerDirection() {
        var totals = TrafficSessionTotals()
        totals.add(inboundRate: -100, outboundRate: 500, elapsed: 1)
        totals.add(inboundRate: .nan, outboundRate: 500, elapsed: 1)

        // Inbound never moves on bad rates; outbound accumulates the two valid ticks.
        XCTAssertEqual(totals.inbound, 0)
        XCTAssertEqual(totals.outbound, 1_000)
    }

    func testNeverGoesBackward() {
        var totals = TrafficSessionTotals()
        totals.add(inboundRate: 500, outboundRate: 500, elapsed: 1)
        let after = totals.inbound
        totals.add(inboundRate: -9_999, outboundRate: 0, elapsed: 1)
        XCTAssertEqual(totals.inbound, after)
    }
}
