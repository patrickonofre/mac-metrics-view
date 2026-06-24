import Foundation

/// Pure decision logic mapping an ambient-light level + the current system
/// appearance to a `ThemeSuggestion`, with three guards against noise:
///
/// - **Hysteresis (dead band):** below `lowLux` ⇒ Dark, above `highLux` ⇒ Light,
///   in between ⇒ no change. The gap between the thresholds stops flip-flopping.
/// - **Dwell:** the level must stay past a threshold for `dwellSeconds` before a
///   suggestion is raised, rejecting a hand passing over the sensor (FR-5).
/// - **Snooze:** a dismissed suggestion is suppressed for that direction until the
///   level returns through the dead band (FR-8).
///
/// Never suggests the appearance already active (FR-6). No I/O and `now` is injected,
/// so dwell/snooze are fully unit-testable without hardware or real time. Owned and
/// called on the main actor by `CPUState`.
final class ThemeSuggestionEngine {
    private let settings: AmbientThemeSettings

    /// The threshold side currently being dwelled on, and when the dwell began.
    private var pendingMode: SystemAppearanceMode?
    private var pendingSince: Date?
    /// A direction the user dismissed; suppressed until the level re-enters the dead band.
    private var snoozedMode: SystemAppearanceMode?

    init(settings: AmbientThemeSettings) {
        self.settings = settings
    }

    func evaluate(lux: Double, current: SystemAppearanceMode, now: Date) -> ThemeSuggestion {
        let candidate = candidateMode(for: lux)

        // Dead band: nothing to suggest. Re-entering it clears both the in-progress
        // dwell (a transient excursion never matures) and any dismissal snooze (FR-8).
        guard let candidate else {
            pendingMode = nil
            pendingSince = nil
            snoozedMode = nil
            return .none
        }

        // The suggested mode is, by construction, only ever the one not currently
        // active (FR-6); if the candidate already matches the system, do nothing.
        guard candidate != current else {
            pendingMode = nil
            pendingSince = nil
            return .none
        }

        // Dismissed this direction — stay quiet until the dead band resets it.
        if snoozedMode == candidate {
            return .none
        }

        // Start (or restart) the dwell when the candidate side changes. Fall through to
        // the elapsed check so a zero dwell suggests on the first qualifying sample.
        if pendingMode != candidate {
            pendingMode = candidate
            pendingSince = now
        }

        // Same side held long enough → suggest.
        if let since = pendingSince, now.timeIntervalSince(since) >= settings.dwellSeconds {
            return .suggest(candidate)
        }
        return .none
    }

    /// Records a user dismissal: suppress this direction until the level returns
    /// through the dead band. A `.none` dismissal is a no-op.
    func dismiss(_ suggestion: ThemeSuggestion) {
        guard case let .suggest(mode) = suggestion else { return }
        snoozedMode = mode
        pendingMode = nil
        pendingSince = nil
    }

    private func candidateMode(for lux: Double) -> SystemAppearanceMode? {
        if lux < settings.lowLux { return .dark }
        if lux > settings.highLux { return .light }
        return nil
    }
}
