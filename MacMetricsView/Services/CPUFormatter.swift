import Foundation

enum CPUMenuBarTextStyle: Equatable {
    case normal
    case elevatedCPU
    case highCPU
}

enum CPUFormatter {
    static let elevatedCPUThreshold = 80.0
    static let highCPUThreshold = 90.0

    static func menuBarTitle(for sample: CPUSample?, showLabel: Bool = true) -> String {
        let value = fixedWidthPercentageString(sample?.totalUsagePercent)
        return showLabel ? "CPU \(value)" : value
    }

    static func menuBarTextStyle(for sample: CPUSample?) -> CPUMenuBarTextStyle {
        guard let sample else { return .normal }

        if sample.totalUsagePercent >= highCPUThreshold {
            return .highCPU
        }

        if sample.totalUsagePercent >= elevatedCPUThreshold {
            return .elevatedCPU
        }

        return .normal
    }

    static func percentageString(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "--%" }
        let rounded = Int(value.clampedPercent.rounded())
        return "\(rounded)%"
    }

    static func fixedWidthPercentageString(_ value: Double?) -> String {
        guard let value, value.isFinite else { return " --%" }
        let rounded = Int(value.clampedPercent.rounded())
        return String(format: "%3d%%", rounded)
    }
}
