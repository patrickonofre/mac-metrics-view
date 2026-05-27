import Foundation

enum RAMFormatter {
    // Pressure severity thresholds (task-001): distinct from CPU/App-Memory percent-of-total.
    static let elevatedPressureThreshold = 60.0
    static let highPressureThreshold = 80.0

    static func menuBarTitle(
        for sample: RAMSample?,
        metric: MetricDisplaySettings.RAMMenuBarMetric,
        showLabel: Bool = true
    ) -> String {
        let value = valueString(for: sample, metric: metric)
        return showLabel ? "RAM \(value)" : value
    }

    /// Raw value string for the selected metric: App Memory as `N.N GB`, Pressure as `NN%`.
    static func valueString(for sample: RAMSample?, metric: MetricDisplaySettings.RAMMenuBarMetric) -> String {
        switch metric {
        case .appMemory:
            return fixedWidthUsedGBString(sample?.appMemoryGB)
        case .pressure:
            return CPUFormatter.percentageString(sample?.pressurePercent)
        }
    }

    static func usedGBString(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "-- GB" }
        return String(format: "%.1f GB", value)
    }

    static func fixedWidthUsedGBString(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "-- GB" }
        return String(format: "%.1f GB", min(value, 999.9))
    }

    static func menuBarTextStyle(
        for sample: RAMSample?,
        metric: MetricDisplaySettings.RAMMenuBarMetric
    ) -> CPUMenuBarTextStyle {
        guard let sample else { return .normal }

        switch metric {
        case .appMemory:
            return severity(
                for: sample.appMemoryPercent,
                elevated: CPUFormatter.elevatedCPUThreshold,
                high: CPUFormatter.highCPUThreshold
            )
        case .pressure:
            return severity(
                for: sample.pressurePercent,
                elevated: elevatedPressureThreshold,
                high: highPressureThreshold
            )
        }
    }

    private static func severity(for percent: Double, elevated: Double, high: Double) -> CPUMenuBarTextStyle {
        if percent >= high { return .highCPU }
        if percent >= elevated { return .elevatedCPU }
        return .normal
    }
}
