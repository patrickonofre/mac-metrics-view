import Foundation

struct MetricVisibilitySettings: Equatable {
    enum Metric {
        case cpu
        case ram
        case network
        case temperature
    }

    private enum Keys {
        static let showCPU = "MetricVisibilitySettings.showCPU"
        static let showRAM = "MetricVisibilitySettings.showRAM"
        static let showNetwork = "MetricVisibilitySettings.showNetwork"
        static let showTemperature = "MetricVisibilitySettings.showTemperature"
    }

    var showCPU: Bool
    var showRAM: Bool
    var showNetwork: Bool
    var showTemperature: Bool

    init(showCPU: Bool = true, showRAM: Bool = true, showNetwork: Bool = true, showTemperature: Bool = false) {
        self.showCPU = showCPU
        self.showRAM = showRAM
        self.showNetwork = showNetwork
        self.showTemperature = showTemperature
    }

    var hasVisibleMetric: Bool {
        showCPU || showRAM || showNetwork || showTemperature
    }

    static func load(from userDefaults: UserDefaults = .standard) -> MetricVisibilitySettings {
        MetricVisibilitySettings(
            showCPU: bool(forKey: Keys.showCPU, defaultValue: true, userDefaults: userDefaults),
            showRAM: bool(forKey: Keys.showRAM, defaultValue: true, userDefaults: userDefaults),
            showNetwork: bool(forKey: Keys.showNetwork, defaultValue: true, userDefaults: userDefaults),
            showTemperature: bool(forKey: Keys.showTemperature, defaultValue: false, userDefaults: userDefaults)
        )
    }

    func save(to userDefaults: UserDefaults = .standard) {
        userDefaults.set(showCPU, forKey: Keys.showCPU)
        userDefaults.set(showRAM, forKey: Keys.showRAM)
        userDefaults.set(showNetwork, forKey: Keys.showNetwork)
        userDefaults.set(showTemperature, forKey: Keys.showTemperature)
    }

    private static func bool(forKey key: String, defaultValue: Bool, userDefaults: UserDefaults) -> Bool {
        guard userDefaults.object(forKey: key) != nil else { return defaultValue }
        return userDefaults.bool(forKey: key)
    }
}
