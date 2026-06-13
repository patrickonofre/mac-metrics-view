import Foundation

/// Pure presentation for the battery metric: the menu bar charge-level glyph + value,
/// the low-charge severity style, and the popover detail rows. AppKit/IOKit-free so it
/// is unit-testable (mirrors `TemperatureFormatter`/`DiskFormatter`). Menu bar shows the
/// glyph + percentage only; time/health/cycles live in the popover (ADR-002).
enum BatteryFormatter {
    /// SF Symbol for the menu bar, bucketed by charge, with a `.bolt` variant while
    /// charging. An unknown charge falls back to the empty glyph.
    static func menuBarGlyphName(for sample: BatterySample?) -> String {
        guard let charge = sample?.chargePercent else { return "battery.0" }

        let bucket: String
        switch charge {
        case ..<13:
            bucket = "battery.0"
        case ..<38:
            bucket = "battery.25"
        case ..<63:
            bucket = "battery.50"
        case ..<88:
            bucket = "battery.75"
        default:
            bucket = "battery.100"
        }

        return sample?.isCharging == true ? "\(bucket).bolt" : bucket
    }

    /// The percentage shown after the glyph, or `--` when the charge is unknown.
    static func menuBarValue(for sample: BatterySample?) -> String {
        guard let charge = sample?.chargePercent else { return "--" }
        return "\(charge)%"
    }

    static func menuBarTitle(for sample: BatterySample?, showLabel: Bool = true) -> String {
        let value = menuBarValue(for: sample)
        return showLabel ? "BAT \(value)" : value
    }

    /// Low-charge severity reuses the shared menu bar text-style scale. While charging,
    /// severity is suppressed (the bolt glyph already signals the safe state).
    static func menuBarTextStyle(for sample: BatterySample?) -> CPUMenuBarTextStyle {
        guard let charge = sample?.chargePercent, sample?.isCharging != true else { return .normal }
        if charge <= 10 { return .highCPU }
        if charge <= 20 { return .elevatedCPU }
        return .normal
    }

    /// Popover detail rows: power source, time remaining, health condition, and cycle
    /// count. Empty when no battery is present (the caller shows a "no battery" note).
    static func detailRows(for sample: BatterySample?, _ language: AppLanguage = .current) -> [(label: String, value: String)] {
        guard let sample else { return [] }

        return [
            (Strings.batteryPowerSource(language), powerSourceString(sample, language)),
            (Strings.batteryTimeRemaining(language), timeRemainingString(sample, language)),
            (Strings.batteryHealth(language), sample.healthCondition.localizedName(in: language)),
            (Strings.batteryCycles(language), cycleCountString(sample))
        ]
    }

    static func powerSourceString(_ sample: BatterySample, _ language: AppLanguage = .current) -> String {
        switch sample.powerSource {
        case .ac:
            return Strings.batteryOnAC(language)
        case .battery:
            return Strings.batteryOnBattery(language)
        }
    }

    static func timeRemainingString(_ sample: BatterySample, _ language: AppLanguage = .current) -> String {
        guard let seconds = sample.timeRemaining, seconds > 0 else {
            return Strings.batteryCalculating(language)
        }
        let totalMinutes = Int(seconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return "\(hours)h \(String(format: "%02d", minutes))m"
    }

    static func cycleCountString(_ sample: BatterySample) -> String {
        guard let cycles = sample.cycleCount else { return "--" }
        return "\(cycles)"
    }
}
