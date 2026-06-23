import Foundation
import Darwin

protocol ProcessReading {
    func readSnapshot() -> ProcessCPUSnapshot?
}

enum ProcessNameParser {
    static func parseName(from cString: [CChar]) -> String {
        guard !cString.isEmpty else { return "" }
        if let nullIndex = cString.firstIndex(of: 0) {
            var nullTerminated = Array(cString[..<nullIndex])
            nullTerminated.append(0)
            return nullTerminated.withUnsafeBufferPointer { ptr in
                guard let base = ptr.baseAddress else { return "" }
                return String(cString: base)
            }
        }
        let data = cString.map { UInt8(bitPattern: $0) }
        return String(bytes: data, encoding: .utf8)?
            .trimmingCharacters(in: .controlCharacters) ?? ""
    }
}

final class LibprocProcessReader: ProcessReading {
    private var timebase = mach_timebase_info_data_t()

    /// Per-PID name cache. `proc_name` is the only extra per-process syscall on top of the
    /// CPU read, and a process name never changes for the life of a PID — so we resolve it
    /// once and reuse it on later ticks (PERF-03). In steady state (the same ~hundreds of
    /// PIDs from tick to tick), this drops `proc_name` calls per snapshot from one-per-PID to
    /// one-per-newly-seen-PID, cutting the dominant cost of the 2s process sampler.
    ///
    /// Bounded to the live set: every snapshot prunes entries for PIDs that have exited, so
    /// the cache scales with running processes, not with lifetime PID count. PID reuse can
    /// momentarily surface a stale name (a recycled PID before the next prune), an acceptable
    /// cosmetic edge for a top-CPU list that refreshes every 2s.
    private var nameCache: [pid_t: String] = [:]

    init() {
        mach_timebase_info(&timebase)
        // Fallback to 1:1 if for some reason the timebase is invalid/empty
        if timebase.denom == 0 {
            timebase.numer = 1
            timebase.denom = 1
        }
    }
    
    func readSnapshot() -> ProcessCPUSnapshot? {
        // 1. Get required buffer size for all PIDs
        let expectedSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard expectedSize > 0 else { return nil }
        
        // 2. Allocate buffer and retrieve PIDs
        let numPids = Int(expectedSize / Int32(MemoryLayout<pid_t>.stride))
        var pids = [pid_t](repeating: 0, count: numPids)
        let result = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(expectedSize))
        guard result > 0 else { return nil }
        
        let actualCount = Int(result / Int32(MemoryLayout<pid_t>.stride))
        let activePids = pids.prefix(actualCount)
        
        // 3. Gather information for each active PID
        var entries: [Int32: ProcessCPUSnapshot.Entry] = [:]
        var taskInfo = proc_taskinfo()
        let taskInfoSize = Int32(MemoryLayout<proc_taskinfo>.size)
        var nameBuffer = [CChar](repeating: 0, count: 256)
        
        for pid in activePids {
            guard pid > 0 else { continue }
            
            // Query taskinfo
            let infoResult = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, taskInfoSize)
            guard infoResult == taskInfoSize else {
                // PID might have exited or we don't have permission; skip per ADR-001
                continue
            }
            
            // Resolve the name once per PID and reuse it on later ticks (PERF-03). A failed
            // lookup is not cached, so a transient miss retries next tick instead of pinning
            // a bogus "Unknown".
            let name: String
            if let cached = nameCache[pid] {
                name = cached
            } else {
                let nameResult = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
                if nameResult > 0 {
                    let resolved = ProcessNameParser.parseName(from: nameBuffer)
                    nameCache[pid] = resolved
                    name = resolved
                } else {
                    name = "Unknown"
                }
            }

            // Convert Mach ticks to nanoseconds using the cached timebase
            let totalTicks = taskInfo.pti_total_user + taskInfo.pti_total_system
            let cpuNanos = totalTicks * UInt64(timebase.numer) / UInt64(timebase.denom)

            entries[pid] = ProcessCPUSnapshot.Entry(name: name, cpuNanos: cpuNanos)
        }

        // Prune cache to the live set so memory tracks running processes, not lifetime PIDs.
        if nameCache.count > entries.count {
            nameCache = nameCache.filter { entries[$0.key] != nil }
        }

        return ProcessCPUSnapshot(timestamp: Date(), entries: entries)
    }
}
