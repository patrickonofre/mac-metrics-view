import Foundation

enum DiskFormatter {
    static func menuBarTitle(
        for sample: DiskSample?,
        metric: MetricDisplaySettings.DiskMenuBarMetric,
        showLabel: Bool = true
    ) -> String {
        let value = valueString(for: sample, metric: metric, fixedWidth: false)
        return showLabel ? "DISK \(value)" : value
    }

    static func stableMenuBarTitle(
        for sample: DiskSample?,
        metric: MetricDisplaySettings.DiskMenuBarMetric,
        showLabel: Bool = true
    ) -> String {
        let value = valueString(for: sample, metric: metric, fixedWidth: true)
        return showLabel ? "DISK \(value)" : value
    }

    static func combinedRateString(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "-- B/s" }

        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var scaledValue = value
        var unitIndex = 0

        while scaledValue >= 1024, unitIndex < units.count - 1 {
            scaledValue /= 1024
            unitIndex += 1
        }

        if unitIndex == 0 {
            return "\(Int(scaledValue.rounded())) \(units[unitIndex])"
        }

        return String(format: "%.1f %@", scaledValue, units[unitIndex])
    }

    static func splitRateString(read: Double?, write: Double?) -> String {
        "↓ \(combinedRateString(read)) ↑ \(combinedRateString(write))"
    }

    /// Formats a cumulative byte count (not a rate) into adaptive units.
    static func byteCountString(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var scaledValue = Double(bytes)
        var unitIndex = 0

        while scaledValue >= 1024, unitIndex < units.count - 1 {
            scaledValue /= 1024
            unitIndex += 1
        }

        if unitIndex == 0 {
            return "\(Int(scaledValue.rounded())) \(units[unitIndex])"
        }

        return String(format: "%.1f %@", scaledValue, units[unitIndex])
    }

    static func fixedWidthCombinedRateString(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "--.- MB/s" }

        let megabytesPerSecond = min(value / 1_048_576, 999.9)
        return String(format: "%.1f MB/s", megabytesPerSecond)
    }

    static func fixedWidthSplitRateString(read: Double?, write: Double?) -> String {
        "↓ \(fixedWidthCombinedRateString(read)) ↑ \(fixedWidthCombinedRateString(write))"
    }

    static func menuBarTextStyle(for sample: DiskSample?) -> CPUMenuBarTextStyle {
        guard let sample else { return .normal }

        let total = sample.totalBytesPerSecond
        if total < DiskSeverityThresholds.lowUpperBound {
            return .normal
        }
        if total < DiskSeverityThresholds.mediumUpperBound {
            return .elevatedCPU
        }
        return .highCPU
    }

    private static func valueString(
        for sample: DiskSample?,
        metric: MetricDisplaySettings.DiskMenuBarMetric,
        fixedWidth: Bool
    ) -> String {
        switch metric {
        case .combined:
            let rate = sample.map { $0.totalBytesPerSecond }
            return fixedWidth ? fixedWidthCombinedRateString(rate) : combinedRateString(rate)
        case .split:
            let read = sample?.readBytesPerSecond
            let write = sample?.writeBytesPerSecond
            return fixedWidth ? fixedWidthSplitRateString(read: read, write: write) : splitRateString(read: read, write: write)
        }
    }
}
