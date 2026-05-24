import XCTest
@testable import MacMetricsView

final class NetworkCalculationFormattingAndHistoryTests: XCTestCase {
    func testNetworkCalculationReturnsExpectedRatesForValidCounterDeltas() {
        let previous = NetworkCounterSnapshot(
            timestamp: Date(timeIntervalSince1970: 10),
            receivedBytes: 1_000,
            sentBytes: 2_000
        )
        let current = NetworkCounterSnapshot(
            timestamp: Date(timeIntervalSince1970: 12),
            receivedBytes: 3_048,
            sentBytes: 2_512
        )

        let sample = NetworkSampleCalculator.sample(previous: previous, current: current)

        XCTAssertEqual(sample?.downloadBytesPerSecond, 1_024)
        XCTAssertEqual(sample?.uploadBytesPerSecond, 256)
    }

    func testNetworkCalculationRejectsZeroOrNegativeElapsedTime() {
        let previous = NetworkCounterSnapshot(
            timestamp: Date(timeIntervalSince1970: 10),
            receivedBytes: 1_000,
            sentBytes: 2_000
        )
        let sameTime = NetworkCounterSnapshot(
            timestamp: Date(timeIntervalSince1970: 10),
            receivedBytes: 1_100,
            sentBytes: 2_100
        )
        let earlier = NetworkCounterSnapshot(
            timestamp: Date(timeIntervalSince1970: 9),
            receivedBytes: 1_100,
            sentBytes: 2_100
        )

        XCTAssertNil(NetworkSampleCalculator.sample(previous: previous, current: sameTime))
        XCTAssertNil(NetworkSampleCalculator.sample(previous: previous, current: earlier))
    }

    func testNetworkCalculationRejectsBackwardCounters() {
        let previous = NetworkCounterSnapshot(
            timestamp: Date(timeIntervalSince1970: 10),
            receivedBytes: 1_000,
            sentBytes: 2_000
        )
        let receivedBackward = NetworkCounterSnapshot(
            timestamp: Date(timeIntervalSince1970: 11),
            receivedBytes: 999,
            sentBytes: 2_000
        )
        let sentBackward = NetworkCounterSnapshot(
            timestamp: Date(timeIntervalSince1970: 11),
            receivedBytes: 1_000,
            sentBytes: 1_999
        )

        XCTAssertNil(NetworkSampleCalculator.sample(previous: previous, current: receivedBackward))
        XCTAssertNil(NetworkSampleCalculator.sample(previous: previous, current: sentBackward))
    }

    func testNetworkFormatterUsesAdaptiveUnits() {
        XCTAssertEqual(NetworkFormatter.byteRateString(42), "42 B/s")
        XCTAssertEqual(NetworkFormatter.byteRateString(1_536), "1.5 KB/s")
        XCTAssertEqual(NetworkFormatter.byteRateString(1_572_864), "1.5 MB/s")
        XCTAssertEqual(NetworkFormatter.byteRateString(1_610_612_736), "1.5 GB/s")
    }

    func testNetworkFormatterRejectsInvalidValues() {
        XCTAssertEqual(NetworkFormatter.byteRateString(nil), "-- B/s")
        XCTAssertEqual(NetworkFormatter.byteRateString(.nan), "-- B/s")
        XCTAssertEqual(NetworkFormatter.byteRateString(.infinity), "-- B/s")
        XCTAssertEqual(NetworkFormatter.byteRateString(-1), "-- B/s")
    }

    func testNetworkMenuBarTitleShowsSeparateDownloadAndUploadRates() {
        let sample = NetworkSample(downloadBytesPerSecond: 1_536, uploadBytesPerSecond: 84 * 1024)

        XCTAssertEqual(NetworkFormatter.menuBarTitle(for: sample), "NET ↓ 1.5 KB/s ↑ 84.0 KB/s")
        XCTAssertEqual(NetworkFormatter.menuBarTitle(for: sample, showLabel: false), "↓ 1.5 KB/s ↑ 84.0 KB/s")
        XCTAssertEqual(NetworkFormatter.menuBarTitle(for: nil), "NET ↓ -- B/s ↑ -- B/s")
        XCTAssertEqual(NetworkFormatter.menuBarTitle(for: nil, showLabel: false), "↓ -- B/s ↑ -- B/s")
    }

    func testStableNetworkMenuBarTitleUsesFixedWidthRates() {
        let sample = NetworkSample(downloadBytesPerSecond: 1_536, uploadBytesPerSecond: 84 * 1024)

        XCTAssertEqual(NetworkFormatter.stableMenuBarTitle(for: sample), "NET ↓ 0.0 MB/s ↑ 0.1 MB/s")
        XCTAssertEqual(NetworkFormatter.stableMenuBarTitle(for: sample, showLabel: false), "↓ 0.0 MB/s ↑ 0.1 MB/s")
        XCTAssertEqual(NetworkFormatter.stableMenuBarTitle(for: nil), "NET ↓ --.- MB/s ↑ --.- MB/s")
        XCTAssertEqual(NetworkFormatter.stableMenuBarTitle(for: nil, showLabel: false), "↓ --.- MB/s ↑ --.- MB/s")
    }

    func testNetworkHistoryKeepsCapacityAndDropsOldestSamples() {
        var history = NetworkHistory(capacity: 3)

        history.append(NetworkSample(downloadBytesPerSecond: 1, uploadBytesPerSecond: 10))
        history.append(NetworkSample(downloadBytesPerSecond: 2, uploadBytesPerSecond: 20))
        history.append(NetworkSample(downloadBytesPerSecond: 3, uploadBytesPerSecond: 30))
        history.append(NetworkSample(downloadBytesPerSecond: 4, uploadBytesPerSecond: 40))

        XCTAssertEqual(history.samples.map(\.downloadBytesPerSecond), [2, 3, 4])
    }
}
