import XCTest
@testable import MacMetricsView

final class DiskSampleCalculatorTests: XCTestCase {
    func testCalculatorReturnsExpectedRatesForValidCounterDeltas() {
        let previous = DiskCounterSnapshot(
            timestamp: Date(timeIntervalSince1970: 10),
            bytesRead: 1_000,
            bytesWritten: 2_000
        )
        let current = DiskCounterSnapshot(
            timestamp: Date(timeIntervalSince1970: 12),
            bytesRead: 3_048,
            bytesWritten: 2_512
        )

        let sample = DiskSampleCalculator.sample(previous: previous, current: current)

        XCTAssertEqual(sample?.readBytesPerSecond, 1_024)
        XCTAssertEqual(sample?.writeBytesPerSecond, 256)
        XCTAssertEqual(sample?.timestamp, current.timestamp)
    }

    func testCalculatorRejectsBackwardReadCounter() {
        let previous = DiskCounterSnapshot(
            timestamp: Date(timeIntervalSince1970: 10),
            bytesRead: 1_000,
            bytesWritten: 2_000
        )
        let current = DiskCounterSnapshot(
            timestamp: Date(timeIntervalSince1970: 11),
            bytesRead: 999,
            bytesWritten: 2_000
        )

        XCTAssertNil(DiskSampleCalculator.sample(previous: previous, current: current))
    }

    func testCalculatorRejectsBackwardWriteCounter() {
        let previous = DiskCounterSnapshot(
            timestamp: Date(timeIntervalSince1970: 10),
            bytesRead: 1_000,
            bytesWritten: 2_000
        )
        let current = DiskCounterSnapshot(
            timestamp: Date(timeIntervalSince1970: 11),
            bytesRead: 1_000,
            bytesWritten: 1_999
        )

        XCTAssertNil(DiskSampleCalculator.sample(previous: previous, current: current))
    }

    func testCalculatorRejectsZeroElapsedTime() {
        let previous = DiskCounterSnapshot(
            timestamp: Date(timeIntervalSince1970: 10),
            bytesRead: 1_000,
            bytesWritten: 2_000
        )
        let sameTime = DiskCounterSnapshot(
            timestamp: Date(timeIntervalSince1970: 10),
            bytesRead: 1_100,
            bytesWritten: 2_100
        )

        XCTAssertNil(DiskSampleCalculator.sample(previous: previous, current: sameTime))
    }

    func testCalculatorRejectsNegativeElapsedTime() {
        let previous = DiskCounterSnapshot(
            timestamp: Date(timeIntervalSince1970: 10),
            bytesRead: 1_000,
            bytesWritten: 2_000
        )
        let earlier = DiskCounterSnapshot(
            timestamp: Date(timeIntervalSince1970: 9),
            bytesRead: 1_100,
            bytesWritten: 2_100
        )

        XCTAssertNil(DiskSampleCalculator.sample(previous: previous, current: earlier))
    }
}
