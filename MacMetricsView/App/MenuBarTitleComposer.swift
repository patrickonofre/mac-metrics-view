import Foundation

/// Pure title-composition decisions for the menu-bar status item, kept free of
/// AppKit so they are unit-testable without constructing an `NSStatusItem`. The
/// rendered title itself (attributed string, glyphs) is built in
/// `StatusItemController` and verified by launching the app, per the project's
/// testing standards.
enum MenuBarTitleComposer {

    /// SF Symbol appended after the metrics when an update is available.
    static let updateBadgeSymbolName = "arrow.down.circle.fill"

    /// Whether to append the update badge glyph to the status item title.
    static func showsUpdateBadge(availableVersion: String?) -> Bool {
        guard let v = availableVersion else { return false }
        return !v.isEmpty
    }
}
