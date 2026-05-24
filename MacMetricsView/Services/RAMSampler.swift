import Foundation
import Darwin

protocol RAMReading {
    func readSample() -> RAMSample?
}

final class MachRAMReader: RAMReading {
    // The host port and page size are stable for the process lifetime. Resolving them
    // once avoids leaking a send right on every sample (mach_host_self() returns an
    // owned right each call) and avoids a redundant syscall per tick.
    private let host = mach_host_self()
    private let pageSize: vm_size_t

    init() {
        var size: vm_size_t = 0
        if host_page_size(host, &size) != KERN_SUCCESS {
            size = vm_size_t(vm_kernel_page_size)
        }
        pageSize = size
    }

    func readSample() -> RAMSample? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &stats) { statsPointer in
            statsPointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(host, HOST_VM_INFO64, reboundPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else { return nil }

        let totalBytes = ProcessInfo.processInfo.physicalMemory
        guard totalBytes > 0 else { return nil }

        // Mirror Activity Monitor's "Memory Used" = App Memory + Wired + Compressed,
        // where App Memory ≈ internal pages minus purgeable (reclaimable) pages.
        // Inactive/file-cache pages are treated as available, so they're excluded.
        let internalPages = UInt64(stats.internal_page_count)
        let purgeablePages = UInt64(stats.purgeable_count)
        let appMemoryPages = internalPages > purgeablePages ? internalPages - purgeablePages : 0
        let usedPages = appMemoryPages
            + UInt64(stats.wire_count)
            + UInt64(stats.compressor_page_count)
        let usedBytes = usedPages * UInt64(pageSize)

        let bytesPerGB = 1024.0 * 1024.0 * 1024.0
        let usedGB = Double(usedBytes) / bytesPerGB
        let totalGB = Double(totalBytes) / bytesPerGB
        let usedPercent = Double(usedBytes) / Double(totalBytes) * 100

        guard usedGB.isFinite,
              totalGB.isFinite,
              usedPercent.isFinite,
              usedGB >= 0,
              totalGB > 0
        else {
            return nil
        }

        return RAMSample(
            usedGB: usedGB,
            totalGB: totalGB,
            usedPercent: usedPercent
        )
    }
}

@MainActor
protocol RAMSamplerDelegate: AnyObject {
    func ramSampler(_ sampler: RAMSampler, didProduce sample: RAMSample)
}

@MainActor
final class RAMSampler {
    private let reader: RAMReading
    private let interval: TimeInterval
    private var timer: Timer?

    weak var delegate: RAMSamplerDelegate?

    init(reader: RAMReading = MachRAMReader(), interval: TimeInterval = 1) {
        self.reader = reader
        self.interval = interval
    }

    func start() {
        collect()
        timer = MainRunLoopTimer.repeating(every: interval) { [weak self] in self?.collect() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func collect() {
        guard let sample = reader.readSample() else { return }
        delegate?.ramSampler(self, didProduce: sample)
    }
}
