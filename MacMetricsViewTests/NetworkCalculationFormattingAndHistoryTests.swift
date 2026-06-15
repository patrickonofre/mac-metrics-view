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

    func testCompactFixedWidthRateUsesSingleLetterUnitsInReservedWidth() {
        XCTAssertEqual(NetworkFormatter.compactFixedWidthRate(0), "  0B")
        XCTAssertEqual(NetworkFormatter.compactFixedWidthRate(42), " 42B")
        XCTAssertEqual(NetworkFormatter.compactFixedWidthRate(1_536), "1.5K")
        XCTAssertEqual(NetworkFormatter.compactFixedWidthRate(84 * 1024), " 84K")
        XCTAssertEqual(NetworkFormatter.compactFixedWidthRate(1_572_864), "1.5M")
        XCTAssertEqual(NetworkFormatter.compactFixedWidthRate(1_610_612_736), "1.5G")
        // Every valid token must fit the reserved 4-character field so neighbors never shift.
        let values: [Double] = [0, 42, 999, 1_000, 1_536, 84 * 1024, 1_572_864, 1_610_612_736]
        for value in values {
            XCTAssertEqual(NetworkFormatter.compactFixedWidthRate(value).count, 4)
        }
    }

    func testCompactFixedWidthRateRejectsInvalidValues() {
        XCTAssertEqual(NetworkFormatter.compactFixedWidthRate(nil), "  --")
        XCTAssertEqual(NetworkFormatter.compactFixedWidthRate(.nan), "  --")
        XCTAssertEqual(NetworkFormatter.compactFixedWidthRate(.infinity), "  --")
        XCTAssertEqual(NetworkFormatter.compactFixedWidthRate(-1), "  --")
    }

    func testCompactMenuBarValuePairsDownloadAndUpload() {
        let sample = NetworkSample(downloadBytesPerSecond: 1_536, uploadBytesPerSecond: 84 * 1024)

        XCTAssertEqual(NetworkFormatter.compactMenuBarValue(for: sample), "↓1.5K ↑ 84K")
        XCTAssertEqual(NetworkFormatter.compactMenuBarValue(for: nil), "↓  -- ↑  --")
    }

    func testNetworkHistoryKeepsCapacityAndDropsOldestSamples() {
        var history = NetworkHistory(capacity: 3)

        history.append(NetworkSample(downloadBytesPerSecond: 1, uploadBytesPerSecond: 10))
        history.append(NetworkSample(downloadBytesPerSecond: 2, uploadBytesPerSecond: 20))
        history.append(NetworkSample(downloadBytesPerSecond: 3, uploadBytesPerSecond: 30))
        history.append(NetworkSample(downloadBytesPerSecond: 4, uploadBytesPerSecond: 40))

        XCTAssertEqual(history.samples.map(\.downloadBytesPerSecond), [2, 3, 4])
    }

    // MARK: - Byte-count formatting (totals, not rates)

    func testByteCountStringUsesAdaptiveUnitsWithoutPerSecondSuffix() {
        XCTAssertEqual(NetworkFormatter.byteCountString(42), "42 B")
        XCTAssertEqual(NetworkFormatter.byteCountString(1_536), "1.5 KB")
        XCTAssertEqual(NetworkFormatter.byteCountString(1_572_864), "1.5 MB")
        XCTAssertEqual(NetworkFormatter.byteCountString(1_610_612_736), "1.5 GB")
        XCTAssertEqual(NetworkFormatter.byteCountString(0), "0 B")
    }

    // MARK: - Window stats

    func testRecentTotalBytesIntegratesRatesOverInterval() {
        var history = NetworkHistory(capacity: 45)
        history.append(NetworkSample(downloadBytesPerSecond: 1_000, uploadBytesPerSecond: 100))
        history.append(NetworkSample(downloadBytesPerSecond: 3_000, uploadBytesPerSecond: 300))

        let totals = NetworkWindowStats.recentTotalBytes(in: history, interval: 2)

        // (1000 + 3000) * 2 = 8000 down; (100 + 300) * 2 = 800 up.
        XCTAssertEqual(totals.download, 8_000)
        XCTAssertEqual(totals.upload, 800)
    }

    func testRecentTotalBytesRejectsNonPositiveInterval() {
        var history = NetworkHistory(capacity: 45)
        history.append(NetworkSample(downloadBytesPerSecond: 1_000, uploadBytesPerSecond: 100))

        XCTAssertEqual(NetworkWindowStats.recentTotalBytes(in: history, interval: 0).download, 0)
        XCTAssertEqual(NetworkWindowStats.recentTotalBytes(in: history, interval: -1).upload, 0)
    }

    func testRecentPeakRatesReturnsMaxPerDirection() {
        var history = NetworkHistory(capacity: 45)
        history.append(NetworkSample(downloadBytesPerSecond: 1_000, uploadBytesPerSecond: 500))
        history.append(NetworkSample(downloadBytesPerSecond: 4_000, uploadBytesPerSecond: 200))
        history.append(NetworkSample(downloadBytesPerSecond: 2_000, uploadBytesPerSecond: 900))

        let peaks = NetworkWindowStats.recentPeakRates(in: history)

        XCTAssertEqual(peaks.download, 4_000)
        XCTAssertEqual(peaks.upload, 900)
    }

    func testRecentPeakRatesOnEmptyHistoryIsZero() {
        let peaks = NetworkWindowStats.recentPeakRates(in: NetworkHistory())
        XCTAssertEqual(peaks.download, 0)
        XCTAssertEqual(peaks.upload, 0)
    }

    func testDetailRowsRenderRecentPeaksThenSession() {
        var history = NetworkHistory(capacity: 45)
        history.append(NetworkSample(downloadBytesPerSecond: 1_024, uploadBytesPerSecond: 512))

        var session = TrafficSessionTotals()
        session.add(inboundRate: 3_072, outboundRate: 1_024, elapsed: 1)

        let rows = NetworkFormatter.detailRows(history: history, interval: 1, session: session, .english)

        XCTAssertEqual(rows.count, 6)
        XCTAssertEqual(rows[0].label, "Recent download (~45s)")
        XCTAssertEqual(rows[0].value, "1.0 KB")
        XCTAssertEqual(rows[1].label, "Recent upload (~45s)")
        XCTAssertEqual(rows[2].label, "Peak download (~45s)")
        XCTAssertEqual(rows[2].value, "1.0 KB/s")
        XCTAssertEqual(rows[3].label, "Peak upload (~45s)")
        XCTAssertEqual(rows[4].label, "Session download")
        XCTAssertEqual(rows[4].value, "3.0 KB")
        XCTAssertEqual(rows[5].label, "Session upload")
        XCTAssertEqual(rows[5].value, "1.0 KB")

        // Empty history + zero session still yields six rows so the card never blanks out.
        let emptyRows = NetworkFormatter.detailRows(history: NetworkHistory(), interval: 1, .english)
        XCTAssertEqual(emptyRows.count, 6)
        XCTAssertEqual(emptyRows[0].value, "0 B")
        XCTAssertEqual(emptyRows[2].value, "0 B/s")
        XCTAssertEqual(emptyRows[4].value, "0 B")
    }

    // MARK: - Localization keys

    func testNetworkDetailLabelsNonEmptyInBothLanguagesAndCommunicateWindow() {
        let texts: [LocalizedText] = [
            Strings.netRecentTotalDownload,
            Strings.netRecentTotalUpload,
            Strings.netRecentPeakDownload,
            Strings.netRecentPeakUpload
        ]
        for text in texts {
            XCTAssertFalse(text(.english).isEmpty)
            XCTAssertFalse(text(.portuguese).isEmpty)
            XCTAssertTrue(text(.english).contains("45"))
            XCTAssertTrue(text(.portuguese).contains("45"))
        }
    }

    func testNetworkSessionLabelsNonEmptyAndOmitWindowMarker() {
        let texts: [LocalizedText] = [Strings.netSessionDownload, Strings.netSessionUpload]
        for text in texts {
            XCTAssertFalse(text(.english).isEmpty)
            XCTAssertFalse(text(.portuguese).isEmpty)
            // Session totals are since-launch, not the ~45s window — must not say "45".
            XCTAssertFalse(text(.english).contains("45"))
        }
    }
}
