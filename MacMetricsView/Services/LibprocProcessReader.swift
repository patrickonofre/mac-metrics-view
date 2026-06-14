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
            
            // Query name
            let nameResult = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            let name = nameResult > 0 ? ProcessNameParser.parseName(from: nameBuffer) : "Unknown"
            
            // Convert Mach ticks to nanoseconds using the cached timebase
            let totalTicks = taskInfo.pti_total_user + taskInfo.pti_total_system
            let cpuNanos = totalTicks * UInt64(timebase.numer) / UInt64(timebase.denom)
            
            entries[pid] = ProcessCPUSnapshot.Entry(name: name, cpuNanos: cpuNanos)
        }
        
        return ProcessCPUSnapshot(timestamp: Date(), entries: entries)
    }
}
