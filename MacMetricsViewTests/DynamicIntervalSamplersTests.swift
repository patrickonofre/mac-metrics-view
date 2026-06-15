import XCTest
@testable import MacMetricsView

@MainActor
final class DynamicIntervalSamplersTests: XCTestCase {
    
    // MARK: - CPU Sampler Tests
    
    private final class FakeCPUReader: CPUReading {
        func readSnapshot() -> CPUSnapshot? {
            CPUSnapshot(user: 100, system: 50, idle: 200, nice: 0)
        }
    }
    
    func testCPUSamplerIntervalUpdateAndIdempotency() {
        let reader = FakeCPUReader()
        let sampler = CPUSampler(reader: reader, interval: 1.0)
        
        XCTAssertEqual(sampler.interval, 1.0)
        
        sampler.start()
        // verify calling start again doesn't leak or crash
        sampler.start()
        
        sampler.start(interval: 3.0)
        XCTAssertEqual(sampler.interval, 3.0)
        
        sampler.stop()
        // verify calling stop again is safe
        sampler.stop()
    }
    
    // MARK: - RAM Sampler Tests
    
    private final class FakeRAMReader: RAMReading {
        func readSample() -> RAMSample? {
            RAMSample(usedGB: 8.0, totalGB: 16.0, usedPercent: 50.0, appMemoryGB: 4.0, appMemoryPercent: 25.0, pressurePercent: 10.0)
        }
    }
    
    func testRAMSamplerIntervalUpdateAndIdempotency() {
        let reader = FakeRAMReader()
        let sampler = RAMSampler(reader: reader, interval: 1.0)
        
        XCTAssertEqual(sampler.interval, 1.0)
        
        sampler.start()
        sampler.start()
        
        sampler.start(interval: 2.0)
        XCTAssertEqual(sampler.interval, 2.0)
        
        sampler.stop()
        sampler.stop()
    }
    
    // MARK: - Network Sampler Tests
    
    private final class FakeNetworkReader: NetworkReading {
        func readSnapshot() -> NetworkCounterSnapshot? {
            NetworkCounterSnapshot(timestamp: Date(), receivedBytes: 1000, sentBytes: 500)
        }
    }
    
    func testNetworkSamplerIntervalUpdateAndIdempotency() {
        let reader = FakeNetworkReader()
        let sampler = NetworkSampler(reader: reader, interval: 1.0)
        
        XCTAssertEqual(sampler.interval, 1.0)
        
        sampler.start()
        sampler.start()
        
        sampler.start(interval: 3.0)
        XCTAssertEqual(sampler.interval, 3.0)
        
        sampler.stop()
        sampler.stop()
    }
}
