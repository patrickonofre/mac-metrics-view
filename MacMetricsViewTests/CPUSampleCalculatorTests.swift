import XCTest
@testable import MacMetricsView

final class CPUSampleCalculatorTests: XCTestCase {
    func testReturnsZeroWhenOnlyIdleTicksIncrease() {
        let previous = CPUSnapshot(user: 10, system: 10, idle: 10, nice: 10)
        let current = CPUSnapshot(user: 10, system: 10, idle: 20, nice: 10)

        let sample = CPUSampleCalculator.sample(previous: previous, current: current)

        XCTAssertEqual(sample?.totalUsagePercent, 0)
    }

    func testReturnsOneHundredWhenNoIdleTicksIncrease() {
        let previous = CPUSnapshot(user: 10, system: 10, idle: 10, nice: 10)
        let current = CPUSnapshot(user: 20, system: 20, idle: 10, nice: 20)

        let sample = CPUSampleCalculator.sample(previous: previous, current: current)

        XCTAssertEqual(sample?.totalUsagePercent, 100)
    }

    func testReturnsExpectedPercentageForMixedDeltas() {
        let previous = CPUSnapshot(user: 0, system: 0, idle: 0, nice: 0)
        let current = CPUSnapshot(user: 30, system: 20, idle: 50, nice: 0)

        let sample = CPUSampleCalculator.sample(previous: previous, current: current)

        XCTAssertEqual(sample?.totalUsagePercent, 50)
        XCTAssertEqual(sample?.userUsagePercent, 30)
        XCTAssertEqual(sample?.systemUsagePercent, 20)
        XCTAssertEqual(sample?.idlePercent, 50)
    }

    func testRejectsZeroTotalDelta() {
        let previous = CPUSnapshot(user: 10, system: 10, idle: 10, nice: 10)
        let current = CPUSnapshot(user: 10, system: 10, idle: 10, nice: 10)

        XCTAssertNil(CPUSampleCalculator.sample(previous: previous, current: current))
    }

    func testRejectsBackwardCounters() {
        let previous = CPUSnapshot(user: 10, system: 10, idle: 10, nice: 10)
        let current = CPUSnapshot(user: 9, system: 10, idle: 10, nice: 10)

        XCTAssertNil(CPUSampleCalculator.sample(previous: previous, current: current))
    }
}
