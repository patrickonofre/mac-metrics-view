import Darwin
import Foundation
import IOKit
import IOKit.storage

final class IOKitDiskReader: DiskReading {
    private var cachedDriverService: io_service_t = 0

    deinit {
        releaseCachedService()
    }

    func readSnapshot() -> DiskCounterSnapshot? {
        let service = resolveDriverService()
        guard service != 0 else { return nil }

        guard let statisticsRef = IORegistryEntryCreateCFProperty(
            service,
            kIOBlockStorageDriverStatisticsKey as CFString,
            kCFAllocatorDefault,
            0
        ) else {
            invalidateCache()
            return nil
        }

        guard let statistics = statisticsRef.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        guard let bytesRead = (statistics[kIOBlockStorageDriverStatisticsBytesReadKey] as? NSNumber)?.uint64Value,
              let bytesWritten = (statistics[kIOBlockStorageDriverStatisticsBytesWrittenKey] as? NSNumber)?.uint64Value
        else {
            return nil
        }

        return DiskCounterSnapshot(bytesRead: bytesRead, bytesWritten: bytesWritten)
    }

    private func resolveDriverService() -> io_service_t {
        if cachedDriverService != 0 {
            return cachedDriverService
        }

        guard let bsdName = Self.bootVolumeBSDName(),
              let driver = Self.findBlockStorageDriver(forBSDName: bsdName)
        else {
            return 0
        }

        cachedDriverService = driver
        return cachedDriverService
    }

    private func invalidateCache() {
        releaseCachedService()
    }

    private func releaseCachedService() {
        if cachedDriverService != 0 {
            IOObjectRelease(cachedDriverService)
            cachedDriverService = 0
        }
    }

    // MARK: - Static helpers

    /// Returns the BSD device name backing the root volume (e.g. `"disk3s1s1"`),
    /// stripping the `/dev/` prefix that `statfs.f_mntfromname` reports.
    private static func bootVolumeBSDName() -> String? {
        var stat = statfs()
        guard statfs("/", &stat) == 0 else { return nil }

        let nameByteCount = MemoryLayout.size(ofValue: stat.f_mntfromname)
        let raw = withUnsafePointer(to: &stat.f_mntfromname) { tuplePtr -> String in
            tuplePtr.withMemoryRebound(to: CChar.self, capacity: nameByteCount) {
                String(cString: $0)
            }
        }

        let prefix = "/dev/"
        return raw.hasPrefix(prefix) ? String(raw.dropFirst(prefix.count)) : raw
    }

    /// Resolves the `IOBlockStorageDriver` that owns the `IOMedia` with the given
    /// BSD name by climbing the IOService parent plane until a driver is found.
    /// Returns a retained `io_service_t` the caller must release.
    private static func findBlockStorageDriver(forBSDName bsdName: String) -> io_service_t? {
        guard let matching = IOServiceMatching(kIOMediaClass) as NSMutableDictionary? else {
            return nil
        }
        matching[kIOBSDNameKey] = bsdName

        let media = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard media != 0 else { return nil }

        defer {
            if media != 0 {
                IOObjectRelease(media)
            }
        }

        // Walk parents. Each call to IORegistryEntryGetParentEntry retains the parent;
        // we release each intermediate before climbing further.
        var current = media
        IOObjectRetain(current) // balance the release at the bottom of each loop iteration

        while true {
            var parent: io_registry_entry_t = 0
            let result = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
            IOObjectRelease(current)
            current = 0

            guard result == KERN_SUCCESS, parent != 0 else {
                return nil
            }

            if IOObjectConformsTo(parent, "IOBlockStorageDriver") != 0 {
                return parent
            }

            current = parent
        }
    }
}
