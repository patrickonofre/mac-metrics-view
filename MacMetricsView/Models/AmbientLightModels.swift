import Foundation

/// A single ambient-light reading. `lux` is the value reported by the sensor's
/// "Level" channel (IOHID ALS, offset +0); on Apple Silicon it is monotonic with
/// ambient brightness but not guaranteed to be calibrated lux, so thresholds are
/// tuned to the observed range rather than absolute lux (see ThemeSuggestionEngine).
struct AmbientLightSample: Equatable {
    let lux: Double
    let timestamp: Date

    init(lux: Double, timestamp: Date = Date()) {
        self.lux = lux
        self.timestamp = timestamp
    }
}

/// The macOS system appearance the feature reasons about. Maps to System Events
/// `dark mode` (true = `.dark`) and to `NSApp.effectiveAppearance` on read.
enum SystemAppearanceMode: Equatable {
    case light
    case dark

    var opposite: SystemAppearanceMode {
        self == .light ? .dark : .light
    }
}

/// Output of `ThemeSuggestionEngine`. Invariant (enforced by the engine, not the
/// type): a `.suggest(mode)` is never the appearance currently active — the engine
/// only ever proposes switching to the *other* mode (FR-6).
enum ThemeSuggestion: Equatable {
    case none
    case suggest(SystemAppearanceMode)
}

/// Result of applying a system-appearance change via System Events. `.notAuthorized`
/// maps to AppleScript error `-1743` (TCC Automation denied); the UI surfaces it as
/// guidance to grant Automation in Privacy & Security.
enum AppearanceApplyResult: Equatable {
    case applied
    case notAuthorized
    case failed
}
