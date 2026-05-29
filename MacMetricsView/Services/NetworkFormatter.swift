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

    /// Compact menu-bar rate: adaptive unit, single letter, no "/s", right-justified
    /// into a reserved 4-character field so the value never shifts its neighbors as it
    /// scales between B/K/M/G. Examples: "1.2M", " 84K", "  0B", "9.9G", "  --".
    static func compactFixedWidthRate(_ value: Double?) -> String {
        let field = 4
        func pad(_ token: String) -> String {
            String(repeating: " ", count: max(0, field - token.count)) + token
        }

        guard let value, value.isFinite, value >= 0 else { return pad("--") }

        let units = ["B", "K", "M", "G"]
        var scaled = value
        var unitIndex = 0
        // Scale at 1000 (not 1024) so the integer branch never reaches four digits and
        // the token stays within the reserved width.
        while scaled >= 1000, unitIndex < units.count - 1 {
            scaled /= 1024
            unitIndex += 1
        }

        let number: String
        if unitIndex > 0, scaled < 10 {
            number = String(format: "%.1f", scaled)
        } else {
            number = "\(Int(scaled.rounded()))"
        }

        return pad(number + units[unitIndex])
    }

    /// Compact, fixed-width download/upload pair for the menu bar status item.
    /// Example: "↓1.2M ↑ 84K".
    static func compactMenuBarValue(for sample: NetworkSample?) -> String {
        "↓\(compactFixedWidthRate(sample?.downloadBytesPerSecond)) ↑\(compactFixedWidthRate(sample?.uploadBytesPerSecond))"
    }
}
