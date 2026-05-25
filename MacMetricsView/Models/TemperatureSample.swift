import Foundation

enum TemperatureState: Equatable {
    case normal
    case warm
    case hot
    case critical
    case unavailable

    func localizedName(in language: AppLanguage = .current) -> String {
        let text: LocalizedText
        switch self {
        case .normal:
            text = Strings.tempNormal
        case .warm:
            text = Strings.tempWarm
        case .hot:
            text = Strings.tempHot
        case .critical:
            text = Strings.tempCritical
        case .unavailable:
            text = Strings.unavailable
        }
        return text(language)
    }

    var menuBarTextStyle: CPUMenuBarTextStyle {
        switch self {
        case .normal, .unavailable:
            return .normal
        case .warm:
            return .elevatedCPU
        case .hot, .critical:
            return .highCPU
        }
    }

    /// Normalized 0–100 level for the popover trend, so the thermal state has an
    /// always-available signal to plot (Celsius is optional and not wired yet).
    var trendLevel: Double {
        switch self {
        case .unavailable:
            return 0
        case .normal:
            return 25
        case .warm:
            return 50
        case .hot:
            return 75
        case .critical:
            return 100
        }
    }
}

struct TemperatureSample: Equatable {
    static let plausibleCelsiusRange = 0.0...150.0

    let timestamp: Date
    let celsius: Double?
    let state: TemperatureState

    init?(timestamp: Date = Date(), celsius: Double?, state: TemperatureState) {
        if let celsius {
            guard celsius.isFinite, Self.plausibleCelsiusRange.contains(celsius) else {
                return nil
            }
        }

        self.timestamp = timestamp
        self.celsius = celsius
        self.state = state
    }

    /// Value plotted in the popover trend. Prefers a numeric Celsius reading
    /// (normalized over the plausible range) when available, otherwise falls back to
    /// the thermal state level. Always present, so the trend is never a dead series.
    var trendValue: Double {
        if let celsius {
            return celsius / Self.plausibleCelsiusRange.upperBound * 100
        }
        return state.trendLevel
    }
}
