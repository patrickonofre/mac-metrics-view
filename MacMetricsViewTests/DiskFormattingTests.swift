import XCTest
@testable import MacMetricsView

final class DiskFormattingTests: XCTestCase {
    func testCombinedRateStringFormatsAdaptiveUnits() {
        XCTAssertEqual(DiskFormatter.combinedRateString(42), "42 B/s")
        XCTAssertEqual(DiskFormatter.combinedRateString(1_536), "1.5 KB/s")
        XCTAssertEqual(DiskFormatter.combinedRateString(1_572_864), "1.5 MB/s")
        XCTAssertEqual(DiskFormatter.combinedRateString(1_610_612_736), "1.5 GB/s")
    }

    func testCombinedRateStringRejectsInvalidValues() {
        XCTAssertEqual(DiskFormatter.combinedRateString(nil), "-- B/s")
        XCTAssertEqual(DiskFormatter.combinedRateString(.nan), "-- B/s")
        XCTAssertEqual(DiskFormatter.combinedRateString(.infinity), "-- B/s")
        XCTAssertEqual(DiskFormatter.combinedRateString(-1), "-- B/s")
    }

    func testSplitRateStringRendersReadAndWriteWithArrows() {
        XCTAssertEqual(
            DiskFormatter.splitRateString(read: 1_536, write: 84 * 1024),
            "↓ 1.5 KB/s ↑ 84.0 KB/s"
        )
    }

    func testSplitRateStringWithNilsRendersPlaceholders() {
        XCTAssertEqual(
            DiskFormatter.splitRateString(read: nil, write: nil),
            "↓ -- B/s ↑ -- B/s"
        )
    }

    func testMenuBarTitleCombinedWithLabelPrefixesDisk() {
        let sample = DiskSample(readBytesPerSecond: 800_000, writeBytesPerSecond: 224_000)
        // total = 1_024_000 ≈ 1000 KB/s → "1000.0 KB/s"? Actually 1_024_000 / 1024 = 1000 exactly,
        // which is < 1024, so stays at KB/s.
        // Implementation: 1_024_000 >= 1024 → 1000 (KB/s, unit 1). Output "1000.0 KB/s".
        let result = DiskFormatter.menuBarTitle(for: sample, metric: .combined, showLabel: true)
        XCTAssertTrue(result.hasPrefix("DISK "), "expected DISK prefix, got: \(result)")
        XCTAssertEqual(result, "DISK 1000.0 KB/s")
    }

    func testMenuBarTitleSplitWithoutLabelOmitsLabelAndIncludesArrowGlyphs() {
        let sample = DiskSample(readBytesPerSecond: 1_536, writeBytesPerSecond: 84 * 1024)
        let result = DiskFormatter.menuBarTitle(for: sample, metric: .split, showLabel: false)
        XCTAssertEqual(result, "↓ 1.5 KB/s ↑ 84.0 KB/s")
        XCTAssertFalse(result.contains("DISK"))
    }

    func testMenuBarTitleWithNilSampleStillFormatsPlaceholder() {
        XCTAssertEqual(
            DiskFormatter.menuBarTitle(for: nil, metric: .combined, showLabel: true),
            "DISK -- B/s"
        )
        XCTAssertEqual(
            DiskFormatter.menuBarTitle(for: nil, metric: .split, showLabel: false),
            "↓ -- B/s ↑ -- B/s"
        )
    }

    func testStableMenuBarTitleUsesFixedWidthMegabytes() {
        let sample = DiskSample(readBytesPerSecond: 1_536, writeBytesPerSecond: 84 * 1024)
        XCTAssertEqual(
            DiskFormatter.stableMenuBarTitle(for: sample, metric: .combined, showLabel: true),
            "DISK 0.1 MB/s"
        )
        XCTAssertEqual(
            DiskFormatter.stableMenuBarTitle(for: sample, metric: .split, showLabel: false),
            "↓ 0.0 MB/s ↑ 0.1 MB/s"
        )
        XCTAssertEqual(
            DiskFormatter.stableMenuBarTitle(for: nil, metric: .combined, showLabel: true),
            "DISK --.- MB/s"
        )
    }

    // MARK: - Severity

    func testMenuBarTextStyleForNilSampleIsNormal() {
        XCTAssertEqual(DiskFormatter.menuBarTextStyle(for: nil), .normal)
    }

    func testMenuBarTextStyleIdleReturnsNormal() {
        let sample = DiskSample(readBytesPerSecond: 4_999_999, writeBytesPerSecond: 0)
        XCTAssertEqual(DiskFormatter.menuBarTextStyle(for: sample), .normal)
    }

    func testMenuBarTextStyleGreenBandLowerEdgeReturnsNormal() {
        let sample = DiskSample(readBytesPerSecond: 5_242_880, writeBytesPerSecond: 0)
        XCTAssertEqual(DiskFormatter.menuBarTextStyle(for: sample), .normal)
    }

    func testMenuBarTextStyleYellowBandLowerEdgeReturnsElevated() {
        let sample = DiskSample(readBytesPerSecond: 104_857_600, writeBytesPerSecond: 0)
        XCTAssertEqual(DiskFormatter.menuBarTextStyle(for: sample), .elevatedCPU)
    }

    func testMenuBarTextStyleRedBandLowerEdgeReturnsHigh() {
        let sample = DiskSample(readBytesPerSecond: 838_860_800, writeBytesPerSecond: 0)
        XCTAssertEqual(DiskFormatter.menuBarTextStyle(for: sample), .highCPU)
    }

    func testMenuBarTextStyleCombinesReadAndWriteForSeverity() {
        let sample = DiskSample(readBytesPerSecond: 60 * 1_048_576, writeBytesPerSecond: 60 * 1_048_576)
        XCTAssertEqual(DiskFormatter.menuBarTextStyle(for: sample), .elevatedCPU)
    }
}
