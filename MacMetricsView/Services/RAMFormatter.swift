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

    /// Popover headline: "Used / Total" e.g. `11.2 / 16 GB`. Gives the context a bare GB
    /// lacks ("how much of *my* Mac's RAM"). Total uses whole GB since physical memory is
    /// a round figure.
    static func usedTotalString(used: Double?, total: Double?) -> String {
        guard let used, used.isFinite, used >= 0,
              let total, total.isFinite, total > 0 else { return "-- GB" }
        return String(format: "%.1f / %.0f GB", used, total)
    }

    /// Localized name for a kernel pressure level, or "--" when unavailable.
    static func pressureLevelName(_ level: MemoryPressureLevel?, _ language: AppLanguage = .current) -> String {
        switch level {
        case .normal: return Strings.ramPressureNormal(language)
        case .warning: return Strings.ramPressureWarning(language)
        case .critical: return Strings.ramPressureCritical(language)
        case nil: return "--"
        }
    }

    /// Activity-Monitor-style breakdown for the expanded RAM card.
    static func detailRows(for sample: RAMSample?, _ language: AppLanguage = .current) -> [(label: String, value: String)] {
        guard let sample else { return [] }
        return [
            (Strings.ramAppMemory(language), usedGBString(sample.appMemoryGB)),
            (Strings.ramWired(language), usedGBString(sample.wiredGB)),
            (Strings.ramCompressed(language), usedGBString(sample.compressedGB)),
            (Strings.ramCachedFiles(language), usedGBString(sample.cachedFilesGB)),
            (Strings.ramSwapUsed(language), usedGBString(sample.swapUsedGB)),
            (Strings.ramPressureLevel(language), pressureLevelName(sample.pressureLevel, language))
        ]
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

        // Kernel pressure level is the honest authority for "is memory a problem now",
        // independent of which value is displayed. Fall back to percent-of-total
        // heuristics only when the level is unavailable.
        if let level = sample.pressureLevel {
            switch level {
            case .normal: return .normal
            case .warning: return .elevatedCPU
            case .critical: return .highCPU
            }
        }

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
