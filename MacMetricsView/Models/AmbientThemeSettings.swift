import Foundation

/// User settings for the ambient-light theme suggestion (FR-9). Default **off** —
/// the feature is opt-in so the TCC Automation prompt only ever appears after the
/// user enables it and confirms a suggestion. Thresholds are in the sensor's native
/// "Level" units (not calibrated lux); defaults come from on-device calibration
/// (dark ≈ 130, lit room ≈ 260 on the reference Mac), with a dead band between
/// `lowLux` and `highLux` so the suggestion does not flap.
struct AmbientThemeSettings: Equatable {
    private enum Keys {
        static let isEnabled = "AmbientThemeSettings.isEnabled"
        static let lowLux = "AmbientThemeSettings.lowLux"
        static let highLux = "AmbientThemeSettings.highLux"
        static let dwellSeconds = "AmbientThemeSettings.dwellSeconds"
    }

    /// Below this → suggest Dark. Above `highLux` → suggest Light. Calibrated to the
    /// measured indoor range; refine per hardware if the sensor scale differs.
    static let defaultLowLux: Double = 175
    static let defaultHighLux: Double = 240
    /// How long the level must stay past a threshold before a suggestion is raised
    /// (FR-5), rejecting a hand passing over the sensor or a passing cloud.
    static let defaultDwellSeconds: TimeInterval = 20

    var isEnabled: Bool
    var lowLux: Double
    var highLux: Double
    var dwellSeconds: TimeInterval

    init(
        isEnabled: Bool = false,
        lowLux: Double = AmbientThemeSettings.defaultLowLux,
        highLux: Double = AmbientThemeSettings.defaultHighLux,
        dwellSeconds: TimeInterval = AmbientThemeSettings.defaultDwellSeconds
    ) {
        self.isEnabled = isEnabled
        // A valid band requires highLux > lowLux (a non-empty dead band). An invalid
        // pair (overlap or inversion) would make the engine flip-flop, so fall back to
        // the calibrated default band rather than persist a degenerate configuration.
        if highLux > lowLux {
            self.lowLux = lowLux
            self.highLux = highLux
        } else {
            self.lowLux = AmbientThemeSettings.defaultLowLux
            self.highLux = AmbientThemeSettings.defaultHighLux
        }
        self.dwellSeconds = max(0, dwellSeconds)
    }

    static func load(from userDefaults: UserDefaults = .standard) -> AmbientThemeSettings {
        // `bool(forKey:)` is false for a missing key → default off (opt-in).
        let isEnabled = userDefaults.bool(forKey: Keys.isEnabled)
        // `object(forKey:) as? Double` is nil for a missing key → calibrated default.
        // The init re-validates the band, so a corrupt stored pair degrades to defaults.
        let low = userDefaults.object(forKey: Keys.lowLux) as? Double ?? defaultLowLux
        let high = userDefaults.object(forKey: Keys.highLux) as? Double ?? defaultHighLux
        let dwell = userDefaults.object(forKey: Keys.dwellSeconds) as? TimeInterval ?? defaultDwellSeconds
        return AmbientThemeSettings(isEnabled: isEnabled, lowLux: low, highLux: high, dwellSeconds: dwell)
    }

    func save(to userDefaults: UserDefaults = .standard) {
        userDefaults.set(isEnabled, forKey: Keys.isEnabled)
        userDefaults.set(lowLux, forKey: Keys.lowLux)
        userDefaults.set(highLux, forKey: Keys.highLux)
        userDefaults.set(dwellSeconds, forKey: Keys.dwellSeconds)
    }
}
