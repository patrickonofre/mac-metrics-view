import XCTest
import AppKit
@testable import MacMetricsView

/// Pure resolver tests for `SeverityPalette` (ADR-002). Accent and appearance are
/// injected, so no AppKit rendering is required — mirrors `PopoverTabPresentationTests`.
final class SeverityPaletteTests: XCTestCase {

    private let light = NSAppearance(named: .aqua)!
    private let dark = NSAppearance(named: .darkAqua)!
    private let palette = SeverityPalette()

    private func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    private func components(_ color: NSColor) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let c = color.usingColorSpace(.sRGB)!
        return (c.redComponent, c.greenComponent, c.blueComponent)
    }

    // MARK: - Normal

    func testNormalReturnsAccentWhenContrastSufficient() {
        let accent = srgb(0.0, 0.3, 0.9) // mid blue, dark enough for light bg
        let result = palette.color(role: .normal, accent: accent, appearance: light)
        XCTAssertEqual(result, accent)
    }

    // MARK: - Elevated

    func testElevatedIsWarmerThanCoolAccent() {
        let accent = srgb(0.0, 0.3, 0.9) // cool blue
        let result = palette.color(role: .elevated, accent: accent, appearance: dark)
        let a = components(accent)
        let e = components(result)
        XCTAssertGreaterThan(e.r, a.r, "elevated should pull red up toward amber")
        XCTAssertLessThan(e.b, a.b, "elevated should pull blue down toward amber")
    }

    func testElevatedIsNotPureAmberAnchor() {
        let accent = srgb(0.0, 0.3, 0.9)
        let result = palette.color(role: .elevated, accent: accent, appearance: dark)
        XCTAssertNotEqual(components(result).b, components(palette.amberAnchor).b,
                          "blend keeps a trace of the accent, so it isn't the pure anchor")
    }

    // MARK: - High (safety floor)

    func testHighIsAlwaysCriticalColorAcrossAccents() {
        for accent in [srgb(1, 0, 0), srgb(0, 0, 1), srgb(0, 1, 0)] {
            XCTAssertEqual(palette.color(role: .high, accent: accent, appearance: dark),
                           palette.criticalColor)
        }
    }

    func testHighIgnoresLowContrastAccent() {
        let nearBlack = srgb(0.02, 0.02, 0.02)
        XCTAssertEqual(palette.color(role: .high, accent: nearBlack, appearance: dark),
                       palette.criticalColor)
    }

    // MARK: - Legibility guard

    func testGuardFallsBackForNearWhiteAccentInLight() {
        let nearWhite = srgb(0.98, 0.98, 0.98)
        XCTAssertEqual(palette.color(role: .normal, accent: nearWhite, appearance: light),
                       NSColor.labelColor)
    }

    func testGuardPassesNearWhiteAccentInDark() {
        let nearWhite = srgb(0.98, 0.98, 0.98)
        XCTAssertEqual(palette.color(role: .normal, accent: nearWhite, appearance: dark),
                       nearWhite)
    }

    func testGuardFallsBackForNearBlackAccentInDark() {
        let nearBlack = srgb(0.02, 0.02, 0.02)
        XCTAssertEqual(palette.color(role: .normal, accent: nearBlack, appearance: dark),
                       NSColor.labelColor)
    }

    func testGuardBaselineFlipsWithAppearance() {
        // A near-black accent reads against a light background but not a dark one.
        let nearBlack = srgb(0.02, 0.02, 0.02)
        XCTAssertEqual(palette.color(role: .normal, accent: nearBlack, appearance: light),
                       nearBlack)
        XCTAssertEqual(palette.color(role: .normal, accent: nearBlack, appearance: dark),
                       NSColor.labelColor)
    }

    // MARK: - Conversion failure

    func testNonConvertibleColorFallsBackToLabel() {
        let pattern = NSColor(patternImage: NSImage(size: NSSize(width: 1, height: 1)))
        XCTAssertEqual(palette.color(role: .normal, accent: pattern, appearance: light),
                       NSColor.labelColor)
    }

    // MARK: - Monochrome menu-bar resolver (ADR-002)

    func testMenuBarColorNormalIsLabelColor() {
        XCTAssertEqual(palette.menuBarColor(role: .normal), NSColor.labelColor)
    }

    func testMenuBarColorElevatedIsLabelColorNotAmber() {
        XCTAssertEqual(palette.menuBarColor(role: .elevated), NSColor.labelColor)
        // Elevated collapses to monochrome — it must not be the amber blend.
        XCTAssertNotEqual(palette.menuBarColor(role: .elevated), palette.amberAnchor)
    }

    func testMenuBarColorHighIsCriticalColor() {
        XCTAssertEqual(palette.menuBarColor(role: .high), palette.criticalColor)
    }
}
