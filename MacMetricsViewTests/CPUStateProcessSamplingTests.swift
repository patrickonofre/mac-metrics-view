import XCTest
@testable import MacMetricsView

final class FakeProcessReader: ProcessReading {
    var snapshotToReturn: ProcessCPUSnapshot?
    var readCount = 0
    
    func readSnapshot() -> ProcessCPUSnapshot? {
        readCount += 1
        return snapshotToReturn
    }
}

@MainActor
final class CPUStateProcessSamplingTests: XCTestCase {
    private var processReader: FakeProcessReader!
    
    private func makeState() -> CPUState {
        let suiteName = "MacMetricsViewTests.CPUStateProcessSampling.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        ud.removePersistentDomain(forName: suiteName)
        processReader = FakeProcessReader()
        
        return CPUState(
            userDefaults: ud,
            accessibilityAuthorization: FakeAccessibilityAuthorization(isTrusted: false),
            processReader: processReader
        )
    }
    
    func testBeginProcessSamplingCapturesBaseline() {
        let state = makeState()
        let now = Date()
        let snapshot = ProcessCPUSnapshot(
            timestamp: now,
            entries: [1: .init(name: "p1", cpuNanos: 100)]
        )
        processReader.snapshotToReturn = snapshot
        
        XCTAssertTrue(state.topCPUProcesses.isEmpty)
        XCTAssertEqual(processReader.readCount, 0)
        
        state.beginProcessSampling()
        
        // Should have captured baseline
        XCTAssertEqual(processReader.readCount, 1)
        XCTAssertTrue(state.topCPUProcesses.isEmpty, "Should still be empty after baseline capture before first tick")
        
        state.endProcessSampling()
    }
    
    func testBeginProcessSamplingIsIdempotent() {
        let state = makeState()
        state.beginProcessSampling()
        XCTAssertEqual(processReader.readCount, 1)
        
        // Calling begin again should not trigger another baseline read
        state.beginProcessSampling()
        XCTAssertEqual(processReader.readCount, 1)
        
        state.endProcessSampling()
    }
    
    func testProcessSamplingTickPublishesRankedList() {
        let state = makeState()
        let now = Date()
        
        // 1. Establish baseline
        processReader.snapshotToReturn = ProcessCPUSnapshot(
            timestamp: now,
            entries: [
                1: .init(name: "p1", cpuNanos: 1_000_000_000),
                2: .init(name: "p2", cpuNanos: 2_000_000_000)
            ]
        )
        state.beginProcessSampling()
        XCTAssertEqual(processReader.readCount, 1)
        
        // 2. Setup next snapshot for the tick
        processReader.snapshotToReturn = ProcessCPUSnapshot(
            timestamp: now.addingTimeInterval(2.0),
            entries: [
                1: .init(name: "p1", cpuNanos: 3_000_000_000), // delta = 2e9 / 2s / 1e9 * 100 = 100%
                2: .init(name: "p2", cpuNanos: 5_000_000_000)  // delta = 3e9 / 2s / 1e9 * 100 = 150%
            ]
        )
        
        // 3. Tick
        state.processSamplingTick()
        XCTAssertEqual(processReader.readCount, 2)
        XCTAssertEqual(state.topCPUProcesses.count, 2)
        
        // p2 is 150%, p1 is 100% -> p2 should be first
        let cores = Double(ProcessInfo.processInfo.activeProcessorCount)
        XCTAssertEqual(state.topCPUProcesses[0].pid, 2)
        XCTAssertEqual(state.topCPUProcesses[0].cpuPercent, 150.0 / cores)
        XCTAssertEqual(state.topCPUProcesses[1].pid, 1)
        XCTAssertEqual(state.topCPUProcesses[1].cpuPercent, 100.0 / cores)
        
        state.endProcessSampling()
    }
    
    func testEndProcessSamplingInvalidatesTimerAndClearsSnapshot() {
        let state = makeState()
        state.beginProcessSampling()
        XCTAssertEqual(processReader.readCount, 1)
        
        state.endProcessSampling()
        
        // Ticking after end should be a no-op
        processReader.snapshotToReturn = ProcessCPUSnapshot(
            timestamp: Date(),
            entries: [1: .init(name: "p1", cpuNanos: 100)]
        )
        state.processSamplingTick()
        
        XCTAssertEqual(processReader.readCount, 1, "Should not read from reader after end")
        XCTAssertTrue(state.topCPUProcesses.isEmpty)
    }
    
    func testTickAfterEndIsNoOp() {
        let state = makeState()
        state.beginProcessSampling()
        state.endProcessSampling()
        
        let previousReadCount = processReader.readCount
        state.processSamplingTick()
        
        XCTAssertEqual(processReader.readCount, previousReadCount, "Tick after end should not perform reads")
    }
}
