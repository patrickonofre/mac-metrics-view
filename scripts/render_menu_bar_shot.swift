import AppKit

// Renders the marketing menu-bar hero shot (docs/assets/menu-bar-2.0.png) as a
// transparent PNG with white SF Symbols + values, matching the live status item:
// CPU, RAM, network, temperature, disk, battery. Sits on the dark .menu-bar-shot
// container (#0b0b1f), so glyphs/text are white. Built as one NSAttributedString
// with NSTextAttachment glyphs — the same shape StatusItemController uses.

struct Segment { let symbol: String; let value: String }

// Symbol names mirror StatusItemController.MenuBarMetric.symbolName / BatteryFormatter.
// Values are representative samples in each formatter's real format, kept compact so
// all six metrics fit the 744px shot.
let segments: [Segment] = [
    Segment(symbol: "cpu", value: "37%"),
    Segment(symbol: "memorychip", value: "12.4/16 GB"),
    Segment(symbol: "network", value: "↓1.2M ↑84K"),
    Segment(symbol: "thermometer", value: "61°C"),
    Segment(symbol: "internaldrive", value: "↓4.2M ↑1.1M"),
    Segment(symbol: "battery.75", value: "82%"),
]

let scale: CGFloat = 2
let displayWidth: CGFloat = 744
let displayHeight: CGFloat = 64
let pxWidth = Int(displayWidth * scale)
let pxHeight = Int(displayHeight * scale)

let fontSize: CGFloat = 13 * scale
let symbolPointSize: CGFloat = 13 * scale
let iconTextGap = "\u{2009}"      // thin space between glyph and value
let segmentGap: CGFloat = 16 * scale

let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)

func whiteSymbol(_ name: String) -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else {
        fatalError("missing symbol: \(name)")
    }
    return img
}

func attachment(_ name: String) -> NSAttributedString {
    let img = whiteSymbol(name)
    let cell = NSTextAttachment()
    cell.image = img
    // Vertically center the glyph on the cap height of the font.
    let h = img.size.height
    cell.bounds = NSRect(x: 0, y: font.capHeight / 2 - h / 2, width: img.size.width, height: h)
    return NSAttributedString(attachment: cell)
}

let line = NSMutableAttributedString()
for (i, seg) in segments.enumerated() {
    line.append(attachment(seg.symbol))
    let valueAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
    line.append(NSAttributedString(string: iconTextGap + seg.value, attributes: valueAttrs))
    if i < segments.count - 1 {
        let gapAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: segmentGap)]
        line.append(NSAttributedString(string: "\u{2002}", attributes: gapAttrs)) // en space spacer
    }
}

let lineSize = line.size()

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: pxWidth, pixelsHigh: pxHeight,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("bitmap rep") }

NSGraphicsContext.saveGraphicsState()
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = ctx
// Transparent background — overlay sits on the dark container.

let drawX = (CGFloat(pxWidth) - lineSize.width) / 2
let drawY = (CGFloat(pxHeight) - lineSize.height) / 2
line.draw(at: NSPoint(x: drawX, y: drawY))

ctx.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png encode") }
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs/assets/menu-bar-2.0.png"
try! png.write(to: URL(fileURLWithPath: outPath))
FileHandle.standardError.write("wrote \(outPath) (\(pxWidth)x\(pxHeight)) line=\(Int(lineSize.width))x\(Int(lineSize.height))\n".data(using: .utf8)!)
