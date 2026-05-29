import Foundation

struct MetricVisibilitySettings: Equatable {
    enum Metric {
        case cpu
        case ram
        case network
        case temperature
        case disk
    }

    private enum Keys {
        static let showCPU = "MetricVisibilitySettings.showCPU"
        static let showRAM = "MetricVisibilitySettings.showRAM"
        static let showNetwork = "MetricVisibilitySettings.showNetwork"
        static let showTemperature = "MetricVisibilitySettings.showTemperature"
        static let showDisk = "MetricVisibilitySettings.showDisk"
    }

    var showCPU: Bool
    var showRAM: Bool
    var showNetwork: Bool
    var showTemperature: Bool
    /// Disk defaults to `false` per ADR-005 — matches the Temperature opt-in
    /// precedent and avoids a menu-bar layout shift for existing users on update.
    var showDisk: Bool

    init(
        showCPU: Bool = true,
        showRAM: Bool = true,
        showNetwork: Bool = true,
        showTemperature: Bool = false,
        showDisk: Bool = false
    ) {
        self.showCPU = showCPU
        self.showRAM = showRAM
        self.showNetwork = showNetwork
        self.showTemperature = showTemperature
        self.showDisk = showDisk
    }

    var hasVisibleMetric: Bool {
        showCPU || showRAM || showNetwork || showTemperature || showDisk
    }

    static func load(from userDefaults: UserDefaults = .standard) -> MetricVisibilitySettings {
        MetricVisibilitySettings(
            showCPU: bool(forKey: Keys.showCPU, defaultValue: true, userDefaults: userDefaults),
            showRAM: bool(forKey: Keys.showRAM, defaultValue: true, userDefaults: userDefaults),
            showNetwork: bool(forKey: Keys.showNetwork, defaultValue: true, userDefaults: userDefaults),
            showTemperature: bool(forKey: Keys.showTemperature, defaultValue: false, userDefaults: userDefaults),
            showDisk: bool(forKey: Keys.showDisk, defaultValue: false, userDefaults: userDefaults)
        )
    }

    func save(to userDefaults: UserDefaults = .standard) {
        userDefaults.set(showCPU, forKey: Keys.showCPU)
        userDefaults.set(showRAM, forKey: Keys.showRAM)
        userDefaults.set(showNetwork, forKey: Keys.showNetwork)
        userDefaults.set(showTemperature, forKey: Keys.showTemperature)
        userDefaults.set(showDisk, forKey: Keys.showDisk)
    }

    private static func bool(forKey key: String, defaultValue: Bool, userDefaults: UserDefaults) -> Bool {
        guard userDefaults.object(forKey: key) != nil else { return defaultValue }
        return userDefaults.bool(forKey: key)
    }
}
