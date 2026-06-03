import Foundation

struct MetricVisibilitySettings: Equatable {
    enum Metric {
        case cpu
        case ram
        case network
        case temperature
        case disk
        case tokens
    }

    private enum Keys {
        static let showCPU = "MetricVisibilitySettings.showCPU"
        static let showRAM = "MetricVisibilitySettings.showRAM"
        static let showNetwork = "MetricVisibilitySettings.showNetwork"
        static let showTemperature = "MetricVisibilitySettings.showTemperature"
        static let showDisk = "MetricVisibilitySettings.showDisk"
        static let showTokens = "MetricVisibilitySettings.showTokens"
        static let firstRunPresetApplied = "MetricVisibilitySettings.firstRunPresetApplied"
    }

    /// What a brand-new install shows in the menu bar before the user configures
    /// anything: CPU, RAM, and Temperature on; Network and Disk off. After the user
    /// changes any visibility, their selection is what persists.
    static let firstRunPreset = MetricVisibilitySettings(
        showCPU: true,
        showRAM: true,
        showNetwork: false,
        showTemperature: true,
        showDisk: false,
        showTokens: false
    )

    var showCPU: Bool
    var showRAM: Bool
    var showNetwork: Bool
    var showTemperature: Bool
    /// Disk defaults to `false` per ADR-005 — matches the Temperature opt-in
    /// precedent and avoids a menu-bar layout shift for existing users on update.
    var showDisk: Bool
    /// Tokens default to `false` (ADR-001/005) — opt-in like Disk/Temperature, so an
    /// update never adds a token segment to an existing user's menu bar.
    var showTokens: Bool

    init(
        showCPU: Bool = true,
        showRAM: Bool = true,
        showNetwork: Bool = true,
        showTemperature: Bool = false,
        showDisk: Bool = false,
        showTokens: Bool = false
    ) {
        self.showCPU = showCPU
        self.showRAM = showRAM
        self.showNetwork = showNetwork
        self.showTemperature = showTemperature
        self.showDisk = showDisk
        self.showTokens = showTokens
    }

    var hasVisibleMetric: Bool {
        showCPU || showRAM || showNetwork || showTemperature || showDisk || showTokens
    }

    static func load(from userDefaults: UserDefaults = .standard) -> MetricVisibilitySettings {
        MetricVisibilitySettings(
            showCPU: bool(forKey: Keys.showCPU, defaultValue: true, userDefaults: userDefaults),
            showRAM: bool(forKey: Keys.showRAM, defaultValue: true, userDefaults: userDefaults),
            showNetwork: bool(forKey: Keys.showNetwork, defaultValue: true, userDefaults: userDefaults),
            showTemperature: bool(forKey: Keys.showTemperature, defaultValue: false, userDefaults: userDefaults),
            showDisk: bool(forKey: Keys.showDisk, defaultValue: false, userDefaults: userDefaults),
            showTokens: bool(forKey: Keys.showTokens, defaultValue: false, userDefaults: userDefaults)
        )
    }

    func save(to userDefaults: UserDefaults = .standard) {
        userDefaults.set(showCPU, forKey: Keys.showCPU)
        userDefaults.set(showRAM, forKey: Keys.showRAM)
        userDefaults.set(showNetwork, forKey: Keys.showNetwork)
        userDefaults.set(showTemperature, forKey: Keys.showTemperature)
        userDefaults.set(showDisk, forKey: Keys.showDisk)
        userDefaults.set(showTokens, forKey: Keys.showTokens)
    }

    /// Resolves the visibility to use at launch, applying the first-run preset exactly
    /// once and only to a genuinely fresh install.
    ///
    /// - A brand-new install (`isFreshInstall == true`, no visibility ever stored) gets
    ///   ``firstRunPreset``.
    /// - An existing install that never touched visibility keeps the legacy defaults, so
    ///   an update never silently changes the user's menu bar (opt-in principle, ADR-005).
    /// - Any install that already has stored visibility (the user chose) is honored as-is.
    ///
    /// The resolution is persisted and guarded so it happens once; from then on the user's
    /// own selection is what loads.
    static func resolved(
        from userDefaults: UserDefaults = .standard,
        isFreshInstall: Bool
    ) -> MetricVisibilitySettings {
        if userDefaults.bool(forKey: Keys.firstRunPresetApplied) {
            return load(from: userDefaults)
        }

        let resolved: MetricVisibilitySettings
        if hasStoredVisibility(in: userDefaults) {
            resolved = load(from: userDefaults)
        } else if isFreshInstall {
            resolved = firstRunPreset
        } else {
            resolved = load(from: userDefaults)
        }

        resolved.save(to: userDefaults)
        userDefaults.set(true, forKey: Keys.firstRunPresetApplied)
        return resolved
    }

    private static func hasStoredVisibility(in userDefaults: UserDefaults) -> Bool {
        [Keys.showCPU, Keys.showRAM, Keys.showNetwork, Keys.showTemperature, Keys.showDisk, Keys.showTokens]
            .contains { userDefaults.object(forKey: $0) != nil }
    }

    private static func bool(forKey key: String, defaultValue: Bool, userDefaults: UserDefaults) -> Bool {
        guard userDefaults.object(forKey: key) != nil else { return defaultValue }
        return userDefaults.bool(forKey: key)
    }
}
