import AppKit
import SwiftUI

@MainActor
final class StatusItemController {
    private let state: CPUState
    private let launchAtLoginSettings: LaunchAtLoginSettings
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    // Tinted SF Symbols only change with metric, severity style, and appearance.
    // Caching them keeps the per-tick title rebuild from re-rendering images.
    private var iconCache: [String: NSImage] = [:]
    private var titleUpdateScheduled = false

    init(
        state: CPUState,
        launchAtLoginSettings: LaunchAtLoginSettings
    ) {
        self.state = state
        self.launchAtLoginSettings = launchAtLoginSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()

        configureStatusItem()
        configurePopover()
        updateTitle()
    }

    /// Coalesces title rebuilds: several samplers can deliver in the same run-loop
    /// iteration, and rebuilding the whole title once per delivery is wasted work for
    /// the same visible frame. This collapses them into a single update.
    func setNeedsTitleUpdate() {
        guard !titleUpdateScheduled else { return }
        titleUpdateScheduled = true
        RunLoop.main.perform(inModes: [.common]) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.titleUpdateScheduled = false
                self.updateTitle()
            }
        }
    }

    func updateTitle() {
        guard let button = statusItem.button else { return }

        let attributedTitle = NSMutableAttributedString()
        let separator = NSAttributedString(string: "  ", attributes: baseAttributes(color: .labelColor))

        if state.visibility.showCPU {
            attributedTitle.append(statusSegment(
                metric: .cpu,
                value: CPUFormatter.fixedWidthPercentageString(state.latestSample?.totalUsagePercent),
                style: state.menuBarTextStyle
            ))
        }

        if state.visibility.showRAM {
            if attributedTitle.length > 0 {
                attributedTitle.append(separator)
            }

            attributedTitle.append(statusSegment(
                metric: .ram,
                value: RAMFormatter.fixedWidthUsedGBString(state.latestRAMSample?.usedGB),
                style: state.ramMenuBarTextStyle
            ))
        }

        if state.visibility.showNetwork {
            if attributedTitle.length > 0 {
                attributedTitle.append(separator)
            }

            attributedTitle.append(statusSegment(
                metric: .network,
                value: "↓ \(NetworkFormatter.fixedWidthByteRateString(state.latestNetworkSample?.downloadBytesPerSecond)) ↑ \(NetworkFormatter.fixedWidthByteRateString(state.latestNetworkSample?.uploadBytesPerSecond))",
                style: .normal
            ))
        }

        if state.visibility.showTemperature {
            if attributedTitle.length > 0 {
                attributedTitle.append(separator)
            }

            attributedTitle.append(statusSegment(
                metric: .temperature,
                value: TemperatureFormatter.displayString(for: state.latestTemperatureSample),
                style: state.temperatureMenuBarTextStyle
            ))
        }

        if attributedTitle.length == 0 {
            attributedTitle.append(NSAttributedString(
                string: Strings.metricsPlaceholder(),
                attributes: baseAttributes(color: .labelColor)
            ))
        }

        button.attributedTitle = attributedTitle
        button.setAccessibilityLabel(state.accessibilityMenuBarTitle)
    }

    private func statusSegment(
        metric: MenuBarMetric,
        value: String,
        style: CPUMenuBarTextStyle
    ) -> NSAttributedString {
        let color = color(for: style)
        let segment = NSMutableAttributedString()

        switch state.display.identifierStyle {
        case .labels:
            segment.append(NSAttributedString(
                string: "\(metric.label) ",
                attributes: baseAttributes(color: color)
            ))
        case .icons:
            segment.append(iconAttachment(for: metric, color: color, style: style))
            segment.append(NSAttributedString(
                string: " ",
                attributes: baseAttributes(color: color)
            ))
        }

        segment.append(NSAttributedString(
            string: value,
            attributes: baseAttributes(color: color)
        ))

        return segment
    }

    private func baseAttributes(color: NSColor) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedSystemFont(
                ofSize: max(NSFont.smallSystemFontSize, NSFont.systemFontSize - 2),
                weight: .regular
            ),
            .foregroundColor: color
        ]
    }

    private func color(for style: CPUMenuBarTextStyle) -> NSColor {
        switch style {
        case .normal:
            return .labelColor
        case .elevatedCPU:
            return .systemYellow
        case .highCPU:
            return .systemRed
        }
    }

    private func iconAttachment(for metric: MenuBarMetric, color: NSColor, style: CPUMenuBarTextStyle) -> NSAttributedString {
        let image: NSImage
        if let cached = iconCache[iconCacheKey(for: metric, style: style)] {
            image = cached
        } else {
            guard let symbol = NSImage(
                systemSymbolName: metric.symbolName,
                accessibilityDescription: metric.accessibilityLabel
            )?.withSymbolConfiguration(NSImage.SymbolConfiguration(
                pointSize: max(NSFont.smallSystemFontSize, NSFont.systemFontSize - 2),
                weight: .regular,
                scale: .small
            )) else {
                return NSAttributedString(
                    string: metric.label,
                    attributes: baseAttributes(color: color)
                )
            }

            image = symbol.tinted(with: color)
            iconCache[iconCacheKey(for: metric, style: style)] = image
        }

        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(x: 0, y: -2, width: image.size.width, height: image.size.height)

        return NSAttributedString(attachment: attachment)
    }

    private func iconCacheKey(for metric: MenuBarMetric, style: CPUMenuBarTextStyle) -> String {
        // Appearance is part of the key so a light/dark switch re-tints once and then
        // caches again, instead of baking a stale dynamic color forever.
        let appearance = statusItem.button?.effectiveAppearance.name.rawValue ?? ""
        return "\(metric.symbolName)|\(style)|\(appearance)"
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        button.target = self
        button.action = #selector(togglePopover(_:))
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 380, height: 520)
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(
                state: state,
                launchAtLoginSettings: launchAtLoginSettings,
                dismissPopover: { [weak self] in
                    self?.popover.performClose(nil)
                },
                quit: {
                    NSApplication.shared.terminate(nil)
                }
            )
        )
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            launchAtLoginSettings.refresh()
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

private enum MenuBarMetric {
    case cpu
    case ram
    case network
    case temperature

    var label: String {
        switch self {
        case .cpu:
            return "CPU"
        case .ram:
            return "RAM"
        case .network:
            return "NET"
        case .temperature:
            return "TEMP"
        }
    }

    var symbolName: String {
        switch self {
        case .cpu:
            return "cpu"
        case .ram:
            return "memorychip"
        case .network:
            return "network"
        case .temperature:
            return "thermometer"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .cpu:
            return "CPU"
        case .ram:
            return "RAM"
        case .network:
            return Strings.network()
        case .temperature:
            return Strings.temperature()
        }
    }
}

private extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        color.set()
        let rect = NSRect(origin: .zero, size: size)
        rect.fill()
        draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
