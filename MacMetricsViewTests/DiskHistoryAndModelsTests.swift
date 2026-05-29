import XCTest
@testable import MacMetricsView

final class DiskHistoryAndModelsTests: XCTestCase {
    func testDiskCounterSnapshotRoundTripsViaEquatable() {
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let original = DiskCounterSnapshot(
            timestamp: timestamp,
            bytesRead: 4_096,
            bytesWritten: 8_192
        )
        let copy = DiskCounterSnapshot(
            timestamp: timestamp,
            bytesRead: 4_096,
            bytesWritten: 8_192
        )

        XCTAssertEqual(original, copy)
        XCTAssertEqual(original.timestamp, timestamp)
        XCTAssertEqual(original.bytesRead, 4_096)
        XCTAssertEqual(original.bytesWritten, 8_192)
    }

    func testDiskSampleClampsNegativeReadRateToZero() {
        let sample = DiskSample(readBytesPerSecond: -1, writeBytesPerSecond: 1_000)

        XCTAssertEqual(sample.readBytesPerSecond, 0)
        XCTAssertEqual(sample.writeBytesPerSecond, 1_000)
    }

    func testDiskSampleClampsNaNWriteRateToZero() {
        let sample = DiskSample(readBytesPerSecond: 1_000, writeBytesPerSecond: .nan)

        XCTAssertEqual(sample.readBytesPerSecond, 1_000)
        XCTAssertEqual(sample.writeBytesPerSecond, 0)
    }

    func testDiskSampleTotalBytesPerSecondEqualsReadPlusWrite() {
        let sample = DiskSample(readBytesPerSecond: 1_500, writeBytesPerSecond: 250)

        XCTAssertEqual(sample.totalBytesPerSecond, 1_750)
    }

    func testDiskHistoryKeepsCapacityAndDropsOldestSamples() {
        var history = DiskHistory(capacity: 3)

        history.append(DiskSample(readBytesPerSecond: 1, writeBytesPerSecond: 10))
        history.append(DiskSample(readBytesPerSecond: 2, writeBytesPerSecond: 20))
        history.append(DiskSample(readBytesPerSecond: 3, writeBytesPerSecond: 30))
        history.append(DiskSample(readBytesPerSecond: 4, writeBytesPerSecond: 40))

        XCTAssertEqual(history.samples.map(\.readBytesPerSecond), [2, 3, 4])
        XCTAssertEqual(history.samples.map(\.writeBytesPerSecond), [20, 30, 40])
    }

    func testDiskHistoryClampsNonPositiveCapacityToOne() {
        var history = DiskHistory(capacity: 0)
        XCTAssertEqual(history.capacity, 1)

        history.append(DiskSample(readBytesPerSecond: 1, writeBytesPerSecond: 1))
        history.append(DiskSample(readBytesPerSecond: 2, writeBytesPerSecond: 2))

        XCTAssertEqual(history.samples.map(\.readBytesPerSecond), [2])

        let negativeCapacity = DiskHistory(capacity: -5)
        XCTAssertEqual(negativeCapacity.capacity, 1)
    }
}
