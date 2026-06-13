import Foundation

/// Pure, AppKit/Sparkle-free decisions and copy for the popover update banner.
/// Driven solely by CPUState.availableUpdateVersion so it is unit-testable.
enum UpdateBannerPresentation {
    /// Show the banner only when a newer version is known.
    static func showsBanner(availableVersion: String?) -> Bool {
        guard let v = availableVersion else { return false }
        return !v.isEmpty
    }

    /// Localized headline, e.g. "New version 1.9.1 available".
    static func title(for version: String, _ language: AppLanguage = .current) -> String {
        Strings.autoUpdateAvailable(version, language)
    }

    /// Destination URL for the release notes of a given version.
    static func releaseNotesURL(for version: String) -> URL? {
        URL(string: "https://github.com/patrickonofre/mac-metrics-view/releases/tag/v\(version)")
    }
}
