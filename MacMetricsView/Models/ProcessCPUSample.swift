import Foundation

struct ProcessCPUSnapshot: Equatable {
    struct Entry: Equatable {
        let name: String
        let cpuNanos: UInt64
    }
    let timestamp: Date
    let entries: [Int32: Entry]
}

struct ProcessCPUSample: Equatable, Identifiable {
    let pid: Int32
    let name: String
    let cpuPercent: Double
    var id: Int32 { pid }
}

enum ProcessCPURanking {
    static func topProcesses(
        previous: ProcessCPUSnapshot,
        current: ProcessCPUSnapshot,
        limit: Int = 5,
        activeProcessorCount: Int = ProcessInfo.processInfo.activeProcessorCount
    ) -> [ProcessCPUSample] {
        let elapsed = current.timestamp.timeIntervalSince(previous.timestamp)
        guard elapsed > 0, activeProcessorCount > 0 else { return [] }
        let cores = Double(activeProcessorCount)
        
        return current.entries.compactMap { pid, cur -> ProcessCPUSample? in
            guard let prev = previous.entries[pid],
                  cur.cpuNanos >= prev.cpuNanos
            else {
                return nil
            }
            
            let deltaNanos = cur.cpuNanos - prev.cpuNanos
            let pct = (Double(deltaNanos) / elapsed / 1_000_000_000 * 100) / cores
            
            // Skip zero or negative CPU delta
            guard pct > 0 else { return nil }
            
            return ProcessCPUSample(pid: pid, name: cur.name, cpuPercent: pct)
        }
        .sorted { $0.cpuPercent > $1.cpuPercent }
        .prefix(limit)
        .map { $0 }
    }
}
