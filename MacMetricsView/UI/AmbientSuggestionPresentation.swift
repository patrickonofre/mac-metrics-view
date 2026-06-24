import Foundation

/// Pure decisions and copy for the ambient theme-suggestion banner. Driven by
/// `CPUState.themeSuggestion` + `lastAppearanceApplyResult`, so it is unit-testable
/// without SwiftUI. The denied-Automation state takes priority over an open
/// suggestion so the user is told how to grant permission instead of being offered a
/// switch that cannot apply.
enum AmbientSuggestionPresentation {
    enum BannerState: Equatable {
        case hidden
        /// Offer to switch to `mode` (Apply / Dismiss).
        case suggestion(SystemAppearanceMode)
        /// The last apply was blocked by TCC; show guidance + open-settings.
        case notAuthorized
    }

    static func bannerState(
        suggestion: ThemeSuggestion,
        lastApply: AppearanceApplyResult?
    ) -> BannerState {
        if lastApply == .notAuthorized { return .notAuthorized }
        if case let .suggest(mode) = suggestion { return .suggestion(mode) }
        return .hidden
    }

    static func title(for mode: SystemAppearanceMode, _ language: AppLanguage = .current) -> String {
        switch mode {
        case .dark: return Strings.ambientSuggestionTitleDark(language)
        case .light: return Strings.ambientSuggestionTitleLight(language)
        }
    }

    /// Deep link to Privacy & Security → Automation for the denied state.
    static func automationSettingsURL() -> URL? {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
    }
}
