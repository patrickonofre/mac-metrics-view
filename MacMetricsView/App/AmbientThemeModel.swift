import Foundation
import Combine

/// The Ambient pillar (TD-012): the latest ambient-light reading, the derived theme
/// suggestion, and the opt-in settings driving `ThemeSuggestionEngine`. Extracted from
/// `CPUState` (spec `spec-cpustate-pillar-decouple`, task-003) as an independent,
/// testable `@MainActor ObservableObject`. Persistence stays on `AmbientThemeSettings`
/// (unchanged keys, no migration).
@MainActor
final class AmbientThemeModel: ObservableObject {
    /// Latest ambient-light reading, or `nil` when no ALS is present / not yet sampled.
    @Published private(set) var latestSample: AmbientLightSample?
    /// Current ambient-light theme suggestion (FR-7), or `.none`. Recomputed on each
    /// ambient sample through `ThemeSuggestionEngine`; only ever proposes the mode not
    /// currently active (FR-6).
    @Published private(set) var suggestion: ThemeSuggestion = .none
    /// Result of the most recent apply attempt, so the banner can show the
    /// denied-Automation guidance (`.notAuthorized`). `nil` until the user applies.
    @Published private(set) var lastApplyResult: AppearanceApplyResult?
    /// Ambient-light theme settings (opt-in flag, thresholds, dwell). Default off.
    @Published private(set) var settings: AmbientThemeSettings

    private let userDefaults: UserDefaults
    /// Reads/writes the macOS system appearance for the ambient theme suggestion.
    /// Injected so tests can fake the apply without running osascript / needing NSApp.
    private let systemAppearance: SystemAppearanceControlling
    /// Pure decision engine for the ambient theme suggestion; rebuilt when the
    /// thresholds/dwell change so a settings edit takes effect immediately.
    private var engine: ThemeSuggestionEngine

    init(userDefaults: UserDefaults, systemAppearance: SystemAppearanceControlling) {
        self.userDefaults = userDefaults
        self.systemAppearance = systemAppearance
        let loaded = AmbientThemeSettings.load(from: userDefaults)
        settings = loaded
        engine = ThemeSuggestionEngine(settings: loaded)
    }

    /// Records an ambient-light sample and recomputes the theme suggestion. The sample
    /// is always stored (the popover lux row reads it); the suggestion is only computed
    /// while the feature is enabled.
    func update(with sample: AmbientLightSample) {
        latestSample = sample
        refreshSuggestion()
    }

    private func refreshSuggestion() {
        guard settings.isEnabled, let sample = latestSample else {
            suggestion = .none
            return
        }
        suggestion = engine.evaluate(
            lux: sample.lux,
            current: systemAppearance.current,
            now: Date()
        )
    }

    /// Applies the active suggestion to the macOS system appearance. On success the
    /// suggestion clears; a denial is published for the banner's guidance state. No-op
    /// when there is no active suggestion.
    func apply() {
        guard case let .suggest(mode) = suggestion else { return }
        let result = systemAppearance.apply(mode)
        lastApplyResult = result
        if result == .applied {
            suggestion = .none
        }
    }

    /// Dismisses the active suggestion: snoozes the engine for this direction until the
    /// level returns through the dead band (FR-8) and clears the banner.
    func dismiss() {
        engine.dismiss(suggestion)
        suggestion = .none
        lastApplyResult = nil
    }

    /// Persists new settings, rebuilds the engine with the new band, and re-evaluates so
    /// the change takes effect at once. Returns whether the settings actually changed, so
    /// the caller (`CPUState`) can decide whether to notify `AppDelegate` to start/stop
    /// the sampler in step with the opt-in flag.
    @discardableResult
    func setSettings(_ newSettings: AmbientThemeSettings) -> Bool {
        guard settings != newSettings else { return false }
        settings = newSettings
        newSettings.save(to: userDefaults)
        engine = ThemeSuggestionEngine(settings: newSettings)
        refreshSuggestion()
        return true
    }
}
