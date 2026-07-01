import Foundation

/// Pure, defensive GPU value → string conversion. Reuses `CPUFormatter`'s
/// percentage formatting and severity thresholds, since GPU utilization is the
/// same kind of 0–100 pressure signal as CPU (FR-5).
enum GPUFormatter {
    /// Menu-bar segment value, fixed-width to avoid jitter. `showLabel` prefixes `GPU`.
    static func menuBarTitle(for sample: GPUSample?, showLabel: Bool = true) -> String {
        let value = CPUFormatter.fixedWidthPercentageString(sample?.utilizationPercent)
        return showLabel ? "GPU \(value)" : value
    }

    /// Popover / row value, e.g. `39%` or `--%` when no sample yet.
    static func percentageString(for sample: GPUSample?) -> String {
        CPUFormatter.percentageString(sample?.utilizationPercent)
    }

    /// Severity colour state, using the **same thresholds as CPU**
    /// (`< 80` normal, `80–<90` elevated, `>= 90` high).
    static func menuBarTextStyle(for sample: GPUSample?) -> CPUMenuBarTextStyle {
        guard let sample else { return .normal }

        if sample.utilizationPercent >= CPUFormatter.highCPUThreshold {
            return .highCPU
        }

        if sample.utilizationPercent >= CPUFormatter.elevatedCPUThreshold {
            return .elevatedCPU
        }

        return .normal
    }
}
