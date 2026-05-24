import Foundation
import MachO

protocol CPUReading {
    func readSnapshot() -> CPUSnapshot?
}

final class MachCPUReader: CPUReading {
    // The host port is stable for the process lifetime. Caching it avoids leaking a
    // send right on every sample (mach_host_self() returns an owned right each call).
    private let host = mach_host_self()

    func readSnapshot() -> CPUSnapshot? {
        var processorInfo: processor_info_array_t?
        var processorInfoCount: mach_msg_type_number_t = 0
        var processorCount: natural_t = 0

        let result = host_processor_info(
            host,
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &processorInfo,
            &processorInfoCount
        )

        guard result == KERN_SUCCESS,
              let processorInfo,
              processorCount > 0
        else {
            return nil
        }

        defer {
            let byteCount = vm_size_t(
                Int(processorInfoCount) * MemoryLayout<integer_t>.stride
            )
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: processorInfo)),
                byteCount
            )
        }

        let stride = Int(CPU_STATE_MAX)
        var user: UInt64 = 0
        var system: UInt64 = 0
        var idle: UInt64 = 0
        var nice: UInt64 = 0

        for cpu in 0..<Int(processorCount) {
            let offset = cpu * stride
            user += UInt64(processorInfo[offset + Int(CPU_STATE_USER)])
            system += UInt64(processorInfo[offset + Int(CPU_STATE_SYSTEM)])
            idle += UInt64(processorInfo[offset + Int(CPU_STATE_IDLE)])
            nice += UInt64(processorInfo[offset + Int(CPU_STATE_NICE)])
        }

        return CPUSnapshot(user: user, system: system, idle: idle, nice: nice)
    }
}
