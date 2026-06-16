import AppKit

/// Single source of truth for the severity → color resolution shared by the menu
/// bar (`StatusItemController`) and the popover (`MetricCard`). Pure and injectable:
/// the accent and appearance are always passed in, never read from global state, so
/// every branch is unit-testable without an AppKit runtime (ADR-002).
///
/// Behaviour (ADR-001):
/// - `.normal`   → the system accent, contrast-guarded.
/// - `.elevated` → the accent blended toward a fixed amber anchor, contrast-guarded.
/// - `.high`     → a fixed red, never accent-derived and never guarded, so the
///                 critical state always reads as danger for any accent.
struct SeverityPalette {

    /// Shared instance used by the views; tests construct their own with custom inputs.
    static let `default` = SeverityPalette()

    /// Warmth target the elevated state blends toward.
    let amberAnchor: NSColor

    /// Blend fraction toward `amberAnchor` for the elevated state (0 = accent, 1 = amber).
    let elevatedBlend: CGFloat

    /// The critical-state color. Fixed red — the safety floor, independent of accent.
    let criticalColor: NSColor

    /// Minimum luminance distance from the menu bar background before the legibility
    /// guard falls back to `labelColor`.
    let minContrast: CGFloat

    init(
        amberAnchor: NSColor = .systemOrange,
        elevatedBlend: CGFloat = 0.6,
        criticalColor: NSColor = .systemRed,
        minContrast: CGFloat = 0.20
    ) {
        self.amberAnchor = amberAnchor
        self.elevatedBlend = elevatedBlend
        self.criticalColor = criticalColor
        self.minContrast = minContrast
    }

    /// Resolves the final value color for a severity role. `accent` is typically
    /// `NSColor.controlAccentColor`; `appearance` is the rendering surface's
    /// effective appearance (light/dark), used to pick the guard's background baseline.
    func color(role: SeverityColorRole, accent: NSColor, appearance: NSAppearance) -> NSColor {
        switch role {
        case .normal:
            return guarded(accent, appearance: appearance)
        case .elevated:
            let warm = accent.blended(withFraction: elevatedBlend, of: amberAnchor) ?? amberAnchor
            return guarded(warm, appearance: appearance)
        case .high:
            // Critical must read as danger regardless of accent — never guarded.
            return criticalColor
        }
    }

    /// Monochrome menu-bar value color (ADR-002): the standard `labelColor` for normal
    /// and elevated — Apple's native menu-bar look, adapting to the light/dark menu bar
    /// at draw time — and the shared `criticalColor` (red) for high, so genuine danger
    /// still stands out. No accent, appearance, or contrast guard: `labelColor` is always
    /// legible and `criticalColor` is appearance-independent.
    func menuBarColor(role: SeverityColorRole) -> NSColor {
        switch role {
        case .normal, .elevated:
            return .labelColor
        case .high:
            return criticalColor
        }
    }

    /// Falls back to the always-legible semantic `labelColor` when `color` lacks
    /// enough luminance contrast against the menu bar background for `appearance`,
    /// or cannot be expressed in sRGB.
    private func guarded(_ color: NSColor, appearance: NSAppearance) -> NSColor {
        guard let luminance = relativeLuminance(of: color) else { return .labelColor }
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let backgroundLuminance: CGFloat = isDark ? 0.0 : 1.0
        return abs(luminance - backgroundLuminance) < minContrast ? .labelColor : color
    }

    /// WCAG relative luminance from sRGB components; `nil` when the color cannot be
    /// converted to sRGB (e.g. a pattern color).
    private func relativeLuminance(of color: NSColor) -> CGFloat? {
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
        func linear(_ component: CGFloat) -> CGFloat {
            component <= 0.03928 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(srgb.redComponent)
             + 0.7152 * linear(srgb.greenComponent)
             + 0.0722 * linear(srgb.blueComponent)
    }
}
