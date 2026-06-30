import Foundation
import IOKit

/// Reads the integrated GPU's instantaneous utilization. Thin adapter: the raw
/// IOAccelerator read lives behind a ``GPUUtilizationSource`` seam so this type's
/// clamping/validation is testable without hardware.
final class IOKitGPUReader: GPUReading {
    private let source: GPUUtilizationSource

    init(source: GPUUtilizationSource = IOAcceleratorUtilizationSource()) {
        self.source = source
    }

    func readSample() -> GPUSample? {
        guard let percent = source.readUtilizationPercent() else { return nil }
        return GPUSample(utilizationPercent: percent)
    }
}

/// Real source: reads `PerformanceStatistics` → `"Device Utilization %"` from the
/// `IOAccelerator` service that exposes it. No root, no entitlement — the same
/// `IORegistryEntryCreateCFProperty` mechanism as `IOKitDiskReader`. The value is
/// instantaneous (0–100), so no two-snapshot delta is needed.
final class IOAcceleratorUtilizationSource: GPUUtilizationSource {
    private static let serviceName = "IOAccelerator"
    private static let statisticsKey = "PerformanceStatistics"
    private static let utilizationKey = "Device Utilization %"

    private var cachedService: io_service_t = 0

    deinit {
        releaseCachedService()
    }

    func readUtilizationPercent() -> Double? {
        let service = resolveService()
        guard service != 0 else { return nil }

        guard let statisticsRef = IORegistryEntryCreateCFProperty(
            service,
            Self.statisticsKey as CFString,
            kCFAllocatorDefault,
            0
        ) else {
            // The accelerator went away (sleep/GPU reset); drop the handle and retry next tick.
            invalidateCache()
            return nil
        }

        guard let statistics = statisticsRef.takeRetainedValue() as? [String: Any],
              let value = (statistics[Self.utilizationKey] as? NSNumber)?.doubleValue
        else {
            return nil
        }

        return value
    }

    /// Resolves — and caches — the `IOAccelerator` node that actually exposes
    /// `PerformanceStatistics["Device Utilization %"]`. More than one accelerator
    /// node can be present (R-3); pick the first that carries the key.
    private func resolveService() -> io_service_t {
        if cachedService != 0 {
            return cachedService
        }

        guard let matching = IOServiceMatching(Self.serviceName) else {
            return 0
        }

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return 0
        }
        defer { IOObjectRelease(iterator) }

        var chosen: io_service_t = 0
        var candidate = IOIteratorNext(iterator)
        while candidate != 0 {
            if chosen == 0, Self.exposesUtilization(candidate) {
                chosen = candidate // retained — released in deinit / invalidateCache
            } else {
                IOObjectRelease(candidate)
            }
            candidate = IOIteratorNext(iterator)
        }

        cachedService = chosen
        return cachedService
    }

    private static func exposesUtilization(_ service: io_service_t) -> Bool {
        guard let statisticsRef = IORegistryEntryCreateCFProperty(
            service,
            statisticsKey as CFString,
            kCFAllocatorDefault,
            0
        ), let statistics = statisticsRef.takeRetainedValue() as? [String: Any] else {
            return false
        }
        return statistics[utilizationKey] != nil
    }

    private func invalidateCache() {
        releaseCachedService()
    }

    private func releaseCachedService() {
        if cachedService != 0 {
            IOObjectRelease(cachedService)
            cachedService = 0
        }
    }
}
