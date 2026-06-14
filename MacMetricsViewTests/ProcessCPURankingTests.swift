import XCTest
@testable import MacMetricsView

final class ProcessCPURankingTests: XCTestCase {
    func testExactPerCorePercentage() {
        let now = Date()
        let previous = ProcessCPUSnapshot(
            timestamp: now,
            entries: [
                1: .init(name: "process1", cpuNanos: 1_000_000_000),
                2: .init(name: "process2", cpuNanos: 2_000_000_000)
            ]
        )
        let current = ProcessCPUSnapshot(
            timestamp: now.addingTimeInterval(2.0),
            entries: [
                1: .init(name: "process1", cpuNanos: 3_000_000_000), // delta = 2e9 ns over 2s = 1e9 ns/s = 100%
                2: .init(name: "process2", cpuNanos: 3_000_000_000)  // delta = 1e9 ns over 2s = 0.5e9 ns/s = 50%
            ]
        )
        
        let ranked = ProcessCPURanking.topProcesses(previous: previous, current: current)
        
        XCTAssertEqual(ranked.count, 2)
        XCTAssertEqual(ranked[0].pid, 1)
        XCTAssertEqual(ranked[0].name, "process1")
        XCTAssertEqual(ranked[0].cpuPercent, 100.0)
        
        XCTAssertEqual(ranked[1].pid, 2)
        XCTAssertEqual(ranked[1].name, "process2")
        XCTAssertEqual(ranked[1].cpuPercent, 50.0)
    }
    
    func testExceedsOneHundredPercentForMultiCore() {
        let now = Date()
        let previous = ProcessCPUSnapshot(
            timestamp: now,
            entries: [
                1: .init(name: "busy", cpuNanos: 0)
            ]
        )
        let current = ProcessCPUSnapshot(
            timestamp: now.addingTimeInterval(2.0),
            entries: [
                1: .init(name: "busy", cpuNanos: 6_800_000_000) // delta = 6.8e9 over 2s = 3.4e9 ns/s = 340%
            ]
        )
        
        let ranked = ProcessCPURanking.topProcesses(previous: previous, current: current)
        
        XCTAssertEqual(ranked.count, 1)
        XCTAssertEqual(ranked[0].pid, 1)
        XCTAssertEqual(ranked[0].cpuPercent, 340.0)
    }
    
    func testResultsSortedDescending() {
        let now = Date()
        let previous = ProcessCPUSnapshot(
            timestamp: now,
            entries: [
                1: .init(name: "p1", cpuNanos: 0),
                2: .init(name: "p2", cpuNanos: 0),
                3: .init(name: "p3", cpuNanos: 0)
            ]
        )
        let current = ProcessCPUSnapshot(
            timestamp: now.addingTimeInterval(1.0),
            entries: [
                1: .init(name: "p1", cpuNanos: 100_000_000), // 10%
                2: .init(name: "p2", cpuNanos: 500_000_000), // 50%
                3: .init(name: "p3", cpuNanos: 300_000_000)  // 30%
            ]
        )
        
        let ranked = ProcessCPURanking.topProcesses(previous: previous, current: current)
        
        XCTAssertEqual(ranked.count, 3)
        XCTAssertEqual(ranked[0].pid, 2)
        XCTAssertEqual(ranked[1].pid, 3)
        XCTAssertEqual(ranked[2].pid, 1)
    }
    
    func testLimitTruncation() {
        let now = Date()
        let previous = ProcessCPUSnapshot(
            timestamp: now,
            entries: [
                1: .init(name: "p1", cpuNanos: 0),
                2: .init(name: "p2", cpuNanos: 0),
                3: .init(name: "p3", cpuNanos: 0),
                4: .init(name: "p4", cpuNanos: 0),
                5: .init(name: "p5", cpuNanos: 0),
                6: .init(name: "p6", cpuNanos: 0)
            ]
        )
        let current = ProcessCPUSnapshot(
            timestamp: now.addingTimeInterval(1.0),
            entries: [
                1: .init(name: "p1", cpuNanos: 600_000_000), // 60%
                2: .init(name: "p2", cpuNanos: 500_000_000), // 50%
                3: .init(name: "p3", cpuNanos: 400_000_000), // 40%
                4: .init(name: "p4", cpuNanos: 300_000_000), // 30%
                5: .init(name: "p5", cpuNanos: 200_000_000), // 20%
                6: .init(name: "p6", cpuNanos: 100_000_000)  // 10%
            ]
        )
        
        let ranked = ProcessCPURanking.topProcesses(previous: previous, current: current, limit: 5)
        
        XCTAssertEqual(ranked.count, 5)
        XCTAssertEqual(ranked.map { $0.pid }, [1, 2, 3, 4, 5])
    }
    
    func testFewerThanLimitReturnsAll() {
        let now = Date()
        let previous = ProcessCPUSnapshot(
            timestamp: now,
            entries: [
                1: .init(name: "p1", cpuNanos: 0),
                2: .init(name: "p2", cpuNanos: 0)
            ]
        )
        let current = ProcessCPUSnapshot(
            timestamp: now.addingTimeInterval(1.0),
            entries: [
                1: .init(name: "p1", cpuNanos: 200_000_000),
                2: .init(name: "p2", cpuNanos: 100_000_000)
            ]
        )
        
        let ranked = ProcessCPURanking.topProcesses(previous: previous, current: current, limit: 5)
        
        XCTAssertEqual(ranked.count, 2)
    }
    
    func testNewProcessIsSkipped() {
        let now = Date()
        let previous = ProcessCPUSnapshot(
            timestamp: now,
            entries: [
                1: .init(name: "p1", cpuNanos: 0)
            ]
        )
        let current = ProcessCPUSnapshot(
            timestamp: now.addingTimeInterval(1.0),
            entries: [
                1: .init(name: "p1", cpuNanos: 100_000_000),
                2: .init(name: "p2", cpuNanos: 200_000_000) // absent in previous
            ]
        )
        
        let ranked = ProcessCPURanking.topProcesses(previous: previous, current: current)
        
        XCTAssertEqual(ranked.count, 1)
        XCTAssertEqual(ranked[0].pid, 1)
    }
    
    func testDecreasedCpuNanosIsSkipped() {
        let now = Date()
        let previous = ProcessCPUSnapshot(
            timestamp: now,
            entries: [
                1: .init(name: "p1", cpuNanos: 500_000_000)
            ]
        )
        let current = ProcessCPUSnapshot(
            timestamp: now.addingTimeInterval(1.0),
            entries: [
                1: .init(name: "p1", cpuNanos: 400_000_000) // decreased (wrapped/reused)
            ]
        )
        
        let ranked = ProcessCPURanking.topProcesses(previous: previous, current: current)
        
        XCTAssertTrue(ranked.isEmpty)
    }
    
    func testNonPositiveElapsedReturnsEmpty() {
        let now = Date()
        let previous = ProcessCPUSnapshot(
            timestamp: now,
            entries: [
                1: .init(name: "p1", cpuNanos: 0)
            ]
        )
        
        // Zero elapsed
        let currentZero = ProcessCPUSnapshot(
            timestamp: now,
            entries: [
                1: .init(name: "p1", cpuNanos: 100_000_000)
            ]
        )
        XCTAssertTrue(ProcessCPURanking.topProcesses(previous: previous, current: currentZero).isEmpty)
        
        // Negative elapsed
        let currentNegative = ProcessCPUSnapshot(
            timestamp: now.addingTimeInterval(-1.0),
            entries: [
                1: .init(name: "p1", cpuNanos: 100_000_000)
            ]
        )
        XCTAssertTrue(ProcessCPURanking.topProcesses(previous: previous, current: currentNegative).isEmpty)
    }
    
    func testZeroDeltasAreSkipped() {
        let now = Date()
        let previous = ProcessCPUSnapshot(
            timestamp: now,
            entries: [
                1: .init(name: "p1", cpuNanos: 100_000_000)
            ]
        )
        let current = ProcessCPUSnapshot(
            timestamp: now.addingTimeInterval(1.0),
            entries: [
                1: .init(name: "p1", cpuNanos: 100_000_000) // delta = 0
            ]
        )
        
        let ranked = ProcessCPURanking.topProcesses(previous: previous, current: current)
        
        XCTAssertTrue(ranked.isEmpty)
    }
}
