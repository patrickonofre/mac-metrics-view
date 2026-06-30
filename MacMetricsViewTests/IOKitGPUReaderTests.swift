import XCTest
@testable import MacMetricsView

private final class StubGPUUtilizationSource: GPUUtilizationSource {
    var nextValue: Double?
    private(set) var readCount = 0

    init(nextValue: Double?) {
        self.nextValue = nextValue
    }

    func readUtilizationPercent() -> Double? {
        readCount += 1
        return nextValue
    }
}

final class IOKitGPUReaderTests: XCTestCase {
    func testReaderWrapsSourceValueIntoSample() {
        let reader = IOKitGPUReader(source: StubGPUUtilizationSource(nextValue: 39))

        XCTAssertEqual(reader.readSample()?.utilizationPercent, 39)
    }

    func testReaderClampsOutOfRangeSourceValue() {
        XCTAssertEqual(IOKitGPUReader(source: StubGPUUtilizationSource(nextValue: 150)).readSample()?.utilizationPercent, 100)
        XCTAssertEqual(IOKitGPUReader(source: StubGPUUtilizationSource(nextValue: -10)).readSample()?.utilizationPercent, 0)
        XCTAssertEqual(IOKitGPUReader(source: StubGPUUtilizationSource(nextValue: .nan)).readSample()?.utilizationPercent, 0)
    }

    func testReaderReturnsNilWhenSourceUnavailable() {
        XCTAssertNil(IOKitGPUReader(source: StubGPUUtilizationSource(nextValue: nil)).readSample())
    }

    func testReaderReadsSourceExactlyOncePerSample() {
        let source = StubGPUUtilizationSource(nextValue: 50)
        let reader = IOKitGPUReader(source: source)

        _ = reader.readSample()
        _ = reader.readSample()

        XCTAssertEqual(source.readCount, 2)
    }

    /// Host-only smoke test. On Apple Silicon the IOAccelerator node exposes
    /// `Device Utilization %`; skip gracefully where it is unavailable.
    func testRealSourceReturnsInRangeValueOnHost() throws {
        guard let value = IOAcceleratorUtilizationSource().readUtilizationPercent() else {
            throw XCTSkip("No IOAccelerator Device Utilization % on this host — skipping smoke test.")
        }

        XCTAssertGreaterThanOrEqual(value, 0)
        XCTAssertLessThanOrEqual(value, 100)
    }

    /// Repeated alloc/dealloc must not crash, exercising the cached-service deinit path.
    func testSourceCreationAndDeallocationDoesNotCrashOverManyIterations() {
        for _ in 0..<32 {
            _ = IOAcceleratorUtilizationSource().readUtilizationPercent()
        }
    }
}
