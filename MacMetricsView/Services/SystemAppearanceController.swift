import AppKit

/// Reads and writes the macOS system appearance. Reading uses
/// `NSApp.effectiveAppearance` (no permission). Writing has no public API, so it goes
/// through System Events via AppleScript — the first write triggers the TCC Automation
/// prompt; a denial surfaces as `.notAuthorized` (AppleScript error `-1743`). Injected
/// behind `SystemAppearanceControlling` so `CPUState` and tests can fake it.
@MainActor
protocol SystemAppearanceControlling {
    var current: SystemAppearanceMode { get }
    func apply(_ mode: SystemAppearanceMode) -> AppearanceApplyResult
}

@MainActor
final class SystemAppearanceController: SystemAppearanceControlling {
    /// AppleScript error for "not authorized to send Apple events" (TCC Automation denied).
    private static let notAuthorizedErrorCode = -1743

    var current: SystemAppearanceMode {
        Self.mode(for: NSApp.effectiveAppearance)
    }

    func apply(_ mode: SystemAppearanceMode) -> AppearanceApplyResult {
        let darkLiteral = (mode == .dark) ? "true" : "false"
        let source = "tell application \"System Events\" to tell appearance preferences to set dark mode to \(darkLiteral)"
        guard let script = NSAppleScript(source: source) else { return .failed }

        var error: NSDictionary?
        script.executeAndReturnError(&error)
        return Self.applyResult(errorCode: error?[NSAppleScript.errorNumber] as? Int)
    }

    /// Maps an `NSAppearance` to the feature's light/dark enum. Mirrors the menu-bar
    /// appearance mapping in `StatusItemController`. Pure → unit-testable without NSApp.
    nonisolated static func mode(for appearance: NSAppearance) -> SystemAppearanceMode {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }

    /// Maps an AppleScript error number (or `nil` for success) to a result. Pure →
    /// unit-testable without running osascript.
    nonisolated static func applyResult(errorCode: Int?) -> AppearanceApplyResult {
        guard let code = errorCode else { return .applied }
        return code == notAuthorizedErrorCode ? .notAuthorized : .failed
    }
}
