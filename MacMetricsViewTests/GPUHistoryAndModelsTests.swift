import XCTest
@testable import MacMetricsView

final class GPUHistoryAndModelsTests: XCTestCase {
    // MARK: - GPUSample clamping

    func testGPUSampleClampsNegativeToZero() {
        XCTAssertEqual(GPUSample(utilizationPercent: -1).utilizationPercent, 0)
    }

    func testGPUSampleClampsAboveHundredToHundred() {
        XCTAssertEqual(GPUSample(utilizationPercent: 137).utilizationPercent, 100)
    }

    func testGPUSampleClampsNaNToZero() {
        XCTAssertEqual(GPUSample(utilizationPercent: .nan).utilizationPercent, 0)
    }

    func testGPUSampleKeepsInRangeValue() {
        XCTAssertEqual(GPUSample(utilizationPercent: 39).utilizationPercent, 39)
    }

    func testGPUSampleEquatableMatchesOnValueAndTimestamp() {
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let a = GPUSample(timestamp: timestamp, utilizationPercent: 39)
        let b = GPUSample(timestamp: timestamp, utilizationPercent: 39)

        XCTAssertEqual(a, b)
    }

    // MARK: - GPUHistory bounding

    func testGPUHistoryKeepsCapacityAndDropsOldestSamples() {
        var history = GPUHistory(capacity: 3)

        history.append(GPUSample(utilizationPercent: 1))
        history.append(GPUSample(utilizationPercent: 2))
        history.append(GPUSample(utilizationPercent: 3))
        history.append(GPUSample(utilizationPercent: 4))

        XCTAssertEqual(history.samples.map(\.utilizationPercent), [2, 3, 4])
    }

    func testGPUHistoryClampsNonPositiveCapacityToOne() {
        var history = GPUHistory(capacity: 0)
        XCTAssertEqual(history.capacity, 1)

        history.append(GPUSample(utilizationPercent: 1))
        history.append(GPUSample(utilizationPercent: 2))
        XCTAssertEqual(history.samples.map(\.utilizationPercent), [2])

        XCTAssertEqual(GPUHistory(capacity: -5).capacity, 1)
    }
}
