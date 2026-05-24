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
}
