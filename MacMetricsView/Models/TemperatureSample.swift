import Foundation

enum TemperatureState: Equatable {
    case normal
    case warm
    case hot
    case critical
    case unavailable

    var localizedName: String {
        switch self {
        case .normal:
            return "Normal"
        case .warm:
            return "Aquecido"
        case .hot:
            return "Quente"
        case .critical:
            return "Crítico"
        case .unavailable:
            return "Indisponível"
        }
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
