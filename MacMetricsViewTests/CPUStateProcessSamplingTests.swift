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

    private final class DeferredExecutor: SamplingExecutor {
        private(set) var queuedReadCount = 0
        private var queuedDeliveries: [() -> Void] = []

        func run<T>(_ read: @escaping () -> T, deliver: @escaping @MainActor (T) -> Void) {
            queuedReadCount += 1
            queuedDeliveries.append {
                let value = read()
                MainActor.assumeIsolated { deliver(value) }
            }
        }

        func completeNext() {
            queuedDeliveries.removeFirst()()
        }
    }
    
    private func makeState(executor: SamplingExecutor = InlineSamplingExecutor()) -> CPUState {
        let suiteName = "MacMetricsViewTests.CPUStateProcessSampling.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        ud.removePersistentDomain(forName: suiteName)
        processReader = FakeProcessReader()
        
        return CPUState(
            userDefaults: ud,
            accessibilityAuthorization: FakeAccessibilityAuthorization(isTrusted: false),
            processReader: processReader,
            samplingExecutor: executor
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
        
        XCTAssertTrue(state.metrics.topCPUProcesses.isEmpty)
        XCTAssertEqual(processReader.readCount, 0)
        
        state.metrics.beginProcessSampling()
        
        // Should have captured baseline
        XCTAssertEqual(processReader.readCount, 1)
        XCTAssertTrue(state.metrics.topCPUProcesses.isEmpty, "Should still be empty after baseline capture before first tick")
        
        state.metrics.endProcessSampling()
    }
    
    func testBeginProcessSamplingIsIdempotent() {
        let state = makeState()
        state.metrics.beginProcessSampling()
        XCTAssertEqual(processReader.readCount, 1)
        
        // Calling begin again should not trigger another baseline read
        state.metrics.beginProcessSampling()
        XCTAssertEqual(processReader.readCount, 1)
        
        state.metrics.endProcessSampling()
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
        state.metrics.beginProcessSampling()
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
        state.metrics.processSamplingTick()
        XCTAssertEqual(processReader.readCount, 2)
        XCTAssertEqual(state.metrics.topCPUProcesses.count, 2)
        
        // p2 is 150%, p1 is 100% -> p2 should be first
        let cores = Double(ProcessInfo.processInfo.activeProcessorCount)
        XCTAssertEqual(state.metrics.topCPUProcesses[0].pid, 2)
        XCTAssertEqual(state.metrics.topCPUProcesses[0].cpuPercent, 150.0 / cores)
        XCTAssertEqual(state.metrics.topCPUProcesses[1].pid, 1)
        XCTAssertEqual(state.metrics.topCPUProcesses[1].cpuPercent, 100.0 / cores)
        
        state.metrics.endProcessSampling()
    }
    
    func testEndProcessSamplingInvalidatesTimerAndClearsSnapshot() {
        let state = makeState()
        state.metrics.beginProcessSampling()
        XCTAssertEqual(processReader.readCount, 1)
        
        state.metrics.endProcessSampling()
        
        // Ticking after end should be a no-op
        processReader.snapshotToReturn = ProcessCPUSnapshot(
            timestamp: Date(),
            entries: [1: .init(name: "p1", cpuNanos: 100)]
        )
        state.metrics.processSamplingTick()
        
        XCTAssertEqual(processReader.readCount, 1, "Should not read from reader after end")
        XCTAssertTrue(state.metrics.topCPUProcesses.isEmpty)
    }
    
    func testTickAfterEndIsNoOp() {
        let state = makeState()
        state.metrics.beginProcessSampling()
        state.metrics.endProcessSampling()
        
        let previousReadCount = processReader.readCount
        state.metrics.processSamplingTick()
        
        XCTAssertEqual(processReader.readCount, previousReadCount, "Tick after end should not perform reads")
    }

    func testBlockedProcessSamplingKeepsOnePendingRefresh() {
        let executor = DeferredExecutor()
        let state = makeState(executor: executor)
        let now = Date()
        processReader.snapshotToReturn = ProcessCPUSnapshot(
            timestamp: now,
            entries: [1: .init(name: "p1", cpuNanos: 1_000_000_000)]
        )

        state.metrics.beginProcessSampling()
        state.metrics.processSamplingTick()
        state.metrics.processSamplingTick()

        XCTAssertEqual(executor.queuedReadCount, 1)

        executor.completeNext()
        XCTAssertEqual(executor.queuedReadCount, 2)

        processReader.snapshotToReturn = ProcessCPUSnapshot(
            timestamp: now.addingTimeInterval(2),
            entries: [1: .init(name: "p1", cpuNanos: 3_000_000_000)]
        )
        executor.completeNext()

        XCTAssertEqual(state.metrics.topCPUProcesses.count, 1)
        state.metrics.endProcessSampling()
    }

    func testEndProcessSamplingDropsInFlightSnapshotAndPendingRefresh() {
        let executor = DeferredExecutor()
        let state = makeState(executor: executor)
        processReader.snapshotToReturn = ProcessCPUSnapshot(
            timestamp: Date(),
            entries: [1: .init(name: "p1", cpuNanos: 1_000_000_000)]
        )

        state.metrics.beginProcessSampling()
        state.metrics.processSamplingTick()
        state.metrics.endProcessSampling()
        executor.completeNext()

        XCTAssertEqual(executor.queuedReadCount, 1)
        XCTAssertTrue(state.metrics.topCPUProcesses.isEmpty)
    }
}
