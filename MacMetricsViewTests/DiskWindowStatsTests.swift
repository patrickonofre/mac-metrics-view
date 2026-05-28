import XCTest
@testable import MacMetricsView

final class DiskWindowStatsTests: XCTestCase {
    private let megabyte: Double = 1_048_576

    func testRecentTotalBytesSumsRatesAcrossWindowAtOneSecondInterval() {
        var history = DiskHistory(capacity: 3)
        history.append(DiskSample(readBytesPerSecond: 10 * megabyte, writeBytesPerSecond: 0))
        history.append(DiskSample(readBytesPerSecond: 20 * megabyte, writeBytesPerSecond: 0))
        history.append(DiskSample(readBytesPerSecond: 30 * megabyte, writeBytesPerSecond: 0))

        let totals = DiskWindowStats.recentTotalBytes(in: history, interval: 1)

        XCTAssertEqual(totals.read, UInt64(60 * megabyte))
        XCTAssertEqual(totals.written, 0)
    }

    func testRecentTotalBytesScalesWithInterval() {
        var history = DiskHistory(capacity: 2)
        history.append(DiskSample(readBytesPerSecond: 1_000, writeBytesPerSecond: 2_000))
        history.append(DiskSample(readBytesPerSecond: 1_000, writeBytesPerSecond: 2_000))

        let totals = DiskWindowStats.recentTotalBytes(in: history, interval: 0.5)

        XCTAssertEqual(totals.read, 1_000)
        XCTAssertEqual(totals.written, 2_000)
    }

    func testRecentTotalBytesReturnsZerosForEmptyHistory() {
        let history = DiskHistory(capacity: 5)

        let totals = DiskWindowStats.recentTotalBytes(in: history, interval: 1)

        XCTAssertEqual(totals.read, 0)
        XCTAssertEqual(totals.written, 0)
    }

    func testRecentTotalBytesReturnsZerosForNonPositiveInterval() {
        var history = DiskHistory(capacity: 1)
        history.append(DiskSample(readBytesPerSecond: 1_000, writeBytesPerSecond: 2_000))

        let zeroInterval = DiskWindowStats.recentTotalBytes(in: history, interval: 0)
        let negativeInterval = DiskWindowStats.recentTotalBytes(in: history, interval: -1)

        XCTAssertEqual(zeroInterval.read, 0)
        XCTAssertEqual(zeroInterval.written, 0)
        XCTAssertEqual(negativeInterval.read, 0)
        XCTAssertEqual(negativeInterval.written, 0)
    }

    func testRecentPeakRatesReturnsMaxPerDirection() {
        var history = DiskHistory(capacity: 3)
        history.append(DiskSample(readBytesPerSecond: 10 * megabyte, writeBytesPerSecond: 0))
        history.append(DiskSample(readBytesPerSecond: 20 * megabyte, writeBytesPerSecond: 0))
        history.append(DiskSample(readBytesPerSecond: 30 * megabyte, writeBytesPerSecond: 0))

        let peaks = DiskWindowStats.recentPeakRates(in: history)

        XCTAssertEqual(peaks.read, 30 * megabyte)
        XCTAssertEqual(peaks.write, 0)
    }

    func testRecentPeakRatesReturnsIndependentMaxForReadAndWrite() {
        var history = DiskHistory(capacity: 3)
        history.append(DiskSample(readBytesPerSecond: 5, writeBytesPerSecond: 100))
        history.append(DiskSample(readBytesPerSecond: 50, writeBytesPerSecond: 10))
        history.append(DiskSample(readBytesPerSecond: 25, writeBytesPerSecond: 60))

        let peaks = DiskWindowStats.recentPeakRates(in: history)

        XCTAssertEqual(peaks.read, 50)
        XCTAssertEqual(peaks.write, 100)
    }

    func testRecentPeakRatesReturnsZerosForEmptyHistory() {
        let history = DiskHistory(capacity: 5)

        let peaks = DiskWindowStats.recentPeakRates(in: history)

        XCTAssertEqual(peaks.read, 0)
        XCTAssertEqual(peaks.write, 0)
    }

    // MARK: - DiskSeverityThresholds

    func testSeverityThresholdsMatchAdr004Values() {
        XCTAssertEqual(DiskSeverityThresholds.idleUpperBound, 5 * 1_048_576)
        XCTAssertEqual(DiskSeverityThresholds.lowUpperBound, 100 * 1_048_576)
        XCTAssertEqual(DiskSeverityThresholds.mediumUpperBound, 800 * 1_048_576)
    }
}
