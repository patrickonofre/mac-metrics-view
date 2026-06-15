import XCTest
import Darwin
@testable import MacMetricsView

final class RAMSampleAndReaderTests: XCTestCase {
    private let pageSize: vm_size_t = 4096
    private let totalBytes: UInt64 = 16 * 1024 * 1024 * 1024 // 16 GiB
    private var totalPages: Double { Double(totalBytes) / Double(pageSize) } // 4_194_304

    private func stats(
        internalPages: natural_t = 0,
        purgeable: natural_t = 0,
        wire: natural_t = 0,
        compressor: natural_t = 0,
        external: natural_t = 0
    ) -> vm_statistics64 {
        var s = vm_statistics64()
        s.internal_page_count = internalPages
        s.purgeable_count = purgeable
        s.wire_count = wire
        s.compressor_page_count = compressor
        s.external_page_count = external
        return s
    }

    private func gb(_ pages: Double) -> Double {
        pages * Double(pageSize) / (1024 * 1024 * 1024)
    }

    func testDerivesAppMemoryAndPressureFromStats() {
        // app = internal − purgeable = 1_500_000 pages; pressure = wire + compr = 1_000_000.
        let s = stats(internalPages: 2_000_000, purgeable: 500_000, wire: 400_000, compressor: 600_000)
        let sample = MachRAMReader.makeSample(stats: s, totalBytes: totalBytes, pageSize: pageSize)
        let r = try! XCTUnwrap(sample)

        XCTAssertEqual(r.appMemoryPercent, 1_500_000 / totalPages * 100, accuracy: 0.001)
        XCTAssertEqual(r.pressurePercent, 1_000_000 / totalPages * 100, accuracy: 0.001)
        XCTAssertEqual(r.appMemoryGB, Double(1_500_000 * 4096) / (1024 * 1024 * 1024), accuracy: 0.001)
    }

    func testUsedComputationUnchanged() {
        // Regression: "Used" must remain app + wire + compressed.
        let s = stats(internalPages: 2_000_000, purgeable: 500_000, wire: 400_000, compressor: 600_000)
        let r = try! XCTUnwrap(MachRAMReader.makeSample(stats: s, totalBytes: totalBytes, pageSize: pageSize))

        let expectedUsedPages = (2_000_000.0 - 500_000.0) + 400_000.0 + 600_000.0 // 2_500_000
        XCTAssertEqual(r.usedPercent, expectedUsedPages / totalPages * 100, accuracy: 0.001)
        XCTAssertEqual(r.totalGB, Double(totalBytes) / (1024 * 1024 * 1024), accuracy: 0.001)
    }

    func testAppMemoryClampsToZeroWhenPurgeableExceedsInternal() {
        let s = stats(internalPages: 100, purgeable: 500, wire: 10_000, compressor: 0)
        let r = try! XCTUnwrap(MachRAMReader.makeSample(stats: s, totalBytes: totalBytes, pageSize: pageSize))

        XCTAssertEqual(r.appMemoryGB, 0)
        XCTAssertEqual(r.appMemoryPercent, 0)
    }

    func testPercentsClampedWhenPagesExceedTotal() {
        // Impossible counts (> total pages) must clamp to 100, never exceed.
        let s = stats(internalPages: 5_000_000, purgeable: 0, wire: 5_000_000, compressor: 0)
        let r = try! XCTUnwrap(MachRAMReader.makeSample(stats: s, totalBytes: totalBytes, pageSize: pageSize))

        XCTAssertEqual(r.appMemoryPercent, 100)
        XCTAssertEqual(r.pressurePercent, 100)
        XCTAssertTrue(r.appMemoryGB.isFinite && r.appMemoryGB >= 0)
    }

    func testZeroTotalBytesYieldsNil() {
        let s = stats(internalPages: 1_000, wire: 1_000)
        XCTAssertNil(MachRAMReader.makeSample(stats: s, totalBytes: 0, pageSize: pageSize))
    }

    func testDerivesBreakdownComponents() {
        let s = stats(internalPages: 2_000_000, purgeable: 500_000, wire: 400_000, compressor: 600_000, external: 800_000)
        let r = try! XCTUnwrap(MachRAMReader.makeSample(stats: s, totalBytes: totalBytes, pageSize: pageSize))

        XCTAssertEqual(r.wiredGB, gb(400_000), accuracy: 0.001)
        XCTAssertEqual(r.compressedGB, gb(600_000), accuracy: 0.001)
        XCTAssertEqual(r.cachedFilesGB, gb(800_000), accuracy: 0.001)
    }

    func testSwapAndPressureLevelPassThrough() {
        let s = stats(internalPages: 1_000_000, wire: 200_000)
        let swapBytes: UInt64 = 2 * 1024 * 1024 * 1024 // 2 GiB
        let r = try! XCTUnwrap(MachRAMReader.makeSample(
            stats: s, totalBytes: totalBytes, pageSize: pageSize,
            swapUsedBytes: swapBytes, pressureLevel: .warning
        ))

        XCTAssertEqual(r.swapUsedGB, 2.0, accuracy: 0.001)
        XCTAssertEqual(r.pressureLevel, .warning)
    }

    func testDefaultsWhenSwapAndPressureUnavailable() {
        let s = stats(internalPages: 1_000_000)
        let r = try! XCTUnwrap(MachRAMReader.makeSample(stats: s, totalBytes: totalBytes, pageSize: pageSize))

        XCTAssertEqual(r.swapUsedGB, 0)
        XCTAssertNil(r.pressureLevel)
    }

    func testPressureLevelMapsSysctlValues() {
        XCTAssertEqual(MemoryPressureLevel(sysctlValue: 1), .normal)
        XCTAssertEqual(MemoryPressureLevel(sysctlValue: 2), .warning)
        XCTAssertEqual(MemoryPressureLevel(sysctlValue: 4), .critical)
        XCTAssertNil(MemoryPressureLevel(sysctlValue: 0))
        XCTAssertNil(MemoryPressureLevel(sysctlValue: 3))
    }
}
