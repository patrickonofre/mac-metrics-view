import Foundation

enum RAMFormatter {
    static func menuBarTitle(for sample: RAMSample?, showLabel: Bool = true) -> String {
        let value = fixedWidthUsedGBString(sample?.usedGB)
        return showLabel ? "RAM \(value)" : value
    }

    static func usedGBString(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "-- GB" }
        return String(format: "%.1f GB", value)
    }

    static func fixedWidthUsedGBString(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "-- GB" }
        return String(format: "%.1f GB", min(value, 999.9))
    }

    static func menuBarTextStyle(for sample: RAMSample?) -> CPUMenuBarTextStyle {
        guard let sample else { return .normal }

        if sample.usedPercent >= CPUFormatter.highCPUThreshold {
            return .highCPU
        }

        if sample.usedPercent >= CPUFormatter.elevatedCPUThreshold {
            return .elevatedCPU
        }

        return .normal
    }
}
