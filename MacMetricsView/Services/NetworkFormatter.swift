import Foundation

enum NetworkFormatter {
    static func menuBarTitle(for sample: NetworkSample?, showLabel: Bool = true) -> String {
        let value = "↓ \(byteRateString(sample?.downloadBytesPerSecond)) ↑ \(byteRateString(sample?.uploadBytesPerSecond))"
        return showLabel ? "NET \(value)" : value
    }

    static func stableMenuBarTitle(for sample: NetworkSample?, showLabel: Bool = true) -> String {
        let value = "↓ \(fixedWidthByteRateString(sample?.downloadBytesPerSecond)) ↑ \(fixedWidthByteRateString(sample?.uploadBytesPerSecond))"
        return showLabel ? "NET \(value)" : value
    }

    static func byteRateString(_ value: Double?) -> String {
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

    static func fixedWidthByteRateString(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "--.- MB/s" }

        let megabytesPerSecond = min(value / 1_048_576, 999.9)
        return String(format: "%.1f MB/s", megabytesPerSecond)
    }
}
