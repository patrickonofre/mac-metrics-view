import Foundation

/// Pure title-composition decisions for the menu-bar status item, kept free of
/// AppKit so they are unit-testable without constructing an `NSStatusItem`. The
/// rendered title itself (attributed string, glyphs) is built in
/// `StatusItemController` and verified by launching the app, per the project's
/// testing standards.
enum MenuBarTitleComposer {

    /// SF Symbol used for the secondary warning glyph appended while the cleaning
    /// permission is missing (ADR-003).
    static let accessibilityWarningSymbolName = "exclamationmark.triangle.fill"

    /// Whether the Accessibility-warning glyph should be appended to the title.
    /// Shown only while the grant is missing; cleared once granted.
    static func showsAccessibilityWarning(isAccessibilityGranted: Bool) -> Bool {
        !isAccessibilityGranted
    }
}
