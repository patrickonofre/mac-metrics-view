import Foundation

enum RAMFormatter {
    // Pressure severity thresholds stay distinct from displayed fullness.
    static let elevatedPressureThreshold = 60.0
    static let highPressureThreshold = 80.0

    static func menuBarTitle(
        for sample: RAMSample?,
        showLabel: Bool = true
    ) -> String {
        let value = valueString(for: sample)
        return showLabel ? "RAM \(value)" : value
    }

    /// Menu-bar RAM is always real used memory over physical total.
    static func valueString(for sample: RAMSample?) -> String {
        menuBarUsedTotalString(used: sample?.usedGB, total: sample?.totalGB)
    }

    /// Compact menu-bar ratio, e.g. `11.2/16 GB` (Memory Used over physical total).
    /// Deliberately tighter than the popover headline's spaced `usedTotalString`
    /// (`11.2 / 16 GB`) to conserve menu-bar width (ADR-002). Total is whole since
    /// physical memory is a round figure; used is clamped like the App Memory path.
    static func menuBarUsedTotalString(used: Double?, total: Double?) -> String {
        guard let used, used.isFinite, used >= 0,
              let total, total.isFinite, total > 0 else { return "--/-- GB" }
        return String(format: "%.1f/%.0f GB", min(used, 999.9), total)
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

    static func menuBarTextStyle(for sample: RAMSample?) -> CPUMenuBarTextStyle {
        guard let sample else { return .normal }

        // Kernel pressure level is the honest authority for "is memory a problem now",
        // independent of displayed fullness. Fall back to a pressure proxy only when
        // the level is unavailable.
        if let level = sample.pressureLevel {
            switch level {
            case .normal: return .normal
            case .warning: return .elevatedCPU
            case .critical: return .highCPU
            }
        }

        // Color means "memory pressure", never "memory fullness": Memory Used can run
        // high on healthy Macs, so coloring by fullness would false-alarm.
        return severity(
            for: sample.pressurePercent,
            elevated: elevatedPressureThreshold,
            high: highPressureThreshold
        )
    }

    private static func severity(for percent: Double, elevated: Double, high: Double) -> CPUMenuBarTextStyle {
        if percent >= high { return .highCPU }
        if percent >= elevated { return .elevatedCPU }
        return .normal
    }
}
