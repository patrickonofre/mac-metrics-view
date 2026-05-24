import Foundation

enum TemperatureFormatter {
    static func menuBarTitle(for sample: TemperatureSample?, showLabel: Bool = true) -> String {
        let value = displayString(for: sample)
        return showLabel ? "TEMP \(value)" : value
    }

    static func displayString(for sample: TemperatureSample?) -> String {
        guard let sample else { return "--" }

        if let celsius = sample.celsius {
            return celsiusString(celsius)
        }

        guard sample.state != .unavailable else { return "--" }
        return sample.state.localizedName()
    }

    static func celsiusString(_ value: Double?) -> String {
        guard let value,
              value.isFinite,
              TemperatureSample.plausibleCelsiusRange.contains(value)
        else {
            return "--"
        }

        return "\(Int(value.rounded())) °C"
    }

    static func menuBarTextStyle(for sample: TemperatureSample?) -> CPUMenuBarTextStyle {
        sample?.state.menuBarTextStyle ?? .normal
    }
}
