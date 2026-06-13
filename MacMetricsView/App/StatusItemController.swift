import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let state: CPUState
    private let launchAtLoginSettings: LaunchAtLoginSettings
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    // Tinted SF Symbols only change with metric, severity style, and appearance.
    // Caching them keeps the per-tick title rebuild from re-rendering images.
    private var iconCache: [String: NSImage] = [:]
    private var titleUpdateScheduled = false
    private var cancellables: Set<AnyCancellable> = []

    init(
        state: CPUState,
        launchAtLoginSettings: LaunchAtLoginSettings
    ) {
        self.state = state
        self.launchAtLoginSettings = launchAtLoginSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()

        super.init()

        configureStatusItem()
        configurePopover()
        updateTitle()

        // The grant state can change without a metric tick (during recovery), so
        // refresh the title — which carries the warning badge — when it flips.
        state.$isAccessibilityGranted
            .removeDuplicates()
            .sink { [weak self] _ in self?.setNeedsTitleUpdate() }
            .store(in: &cancellables)
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
        // Spacing-only grouping: a kerned gap between metrics, wider than the single
        // space inside a metric, so each metric reads as one chunk without a divider glyph.
        var separatorAttributes = baseAttributes(color: .labelColor)
        separatorAttributes[.kern] = 6.0
        let separator = NSAttributedString(string: " ", attributes: separatorAttributes)

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
                value: RAMFormatter.valueString(for: state.latestRAMSample, metric: state.ramMenuBarMetric),
                style: state.ramMenuBarTextStyle
            ))
        }

        if state.visibility.showNetwork {
            if attributedTitle.length > 0 {
                attributedTitle.append(separator)
            }

            attributedTitle.append(statusSegment(
                metric: .network,
                value: NetworkFormatter.compactMenuBarValue(for: state.latestNetworkSample),
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

        if state.visibility.showDisk {
            if attributedTitle.length > 0 {
                attributedTitle.append(separator)
            }

            attributedTitle.append(statusSegment(
                metric: .disk,
                value: DiskFormatter.stableMenuBarTitle(
                    for: state.latestDiskSample,
                    metric: state.diskMenuBarMetric,
                    showLabel: false
                ),
                style: state.diskMenuBarTextStyle
            ))
        }

        if state.visibility.showTokens {
            if attributedTitle.length > 0 {
                attributedTitle.append(separator)
            }

            attributedTitle.append(statusSegment(
                metric: .tokens,
                value: TokenFormatter.menuBarTitle(for: state.tokenAggregate, showLabel: false),
                style: state.tokenMenuBarTextStyle,
                labelOverride: TokenFormatter.menuBarLabel(for: state.tokenProvider)
            ))
        }

        if attributedTitle.length == 0 {
            attributedTitle.append(NSAttributedString(
                string: Strings.metricsPlaceholder(),
                attributes: baseAttributes(color: .labelColor)
            ))
        }

        // Additive, secondary warning glyph while the cleaning permission is
        // missing — never recolors the metric segments (ADR-003).
        if MenuBarTitleComposer.showsAccessibilityWarning(isAccessibilityGranted: state.isAccessibilityGranted) {
            attributedTitle.append(separator)
            attributedTitle.append(warningGlyphAttachment(color: .secondaryLabelColor))
        }

        button.attributedTitle = attributedTitle
        button.setAccessibilityLabel(state.accessibilityMenuBarTitle)
    }

    private func statusSegment(
        metric: MenuBarMetric,
        value: String,
        style: CPUMenuBarTextStyle,
        labelOverride: String? = nil
    ) -> NSAttributedString {
        // Hierarchy: the identifier (icon or label) is always secondary; only the value
        // carries severity color. This keeps severity an accent on the number the user
        // reads, not a tint over the whole chunk.
        let valueColor = color(for: style)
        let identifierColor = NSColor.secondaryLabelColor
        let segment = NSMutableAttributedString()

        switch state.display.identifierStyle {
        case .labels:
            // `labelOverride` lets the token segment show the provider-aware name
            // (Claude / Codex / Combined) instead of the fixed metric label.
            segment.append(NSAttributedString(
                string: "\(labelOverride ?? metric.label) ",
                attributes: baseAttributes(color: identifierColor)
            ))
        case .icons:
            segment.append(iconAttachment(for: metric, color: identifierColor))
            segment.append(NSAttributedString(
                string: " ",
                attributes: baseAttributes(color: identifierColor)
            ))
        }

        segment.append(NSAttributedString(
            string: value,
            attributes: baseAttributes(color: valueColor)
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
            // Orange (not yellow) for contrast in light mode, and to match the popover's
            // severity palette so the same state reads the same in both surfaces.
            return .systemOrange
        case .highCPU:
            return .systemRed
        }
    }

    private func iconAttachment(for metric: MenuBarMetric, color: NSColor) -> NSAttributedString {
        let image: NSImage
        if let cached = iconCache[iconCacheKey(for: metric)] {
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
            iconCache[iconCacheKey(for: metric)] = image
        }

        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(x: 0, y: -2, width: image.size.width, height: image.size.height)

        return NSAttributedString(attachment: attachment)
    }

    /// The secondary warning glyph appended to the title while the cleaning
    /// permission is missing. Cached per appearance like the metric icons, so the
    /// per-tick title rebuild does not re-render it.
    private func warningGlyphAttachment(color: NSColor) -> NSAttributedString {
        let appearance = statusItem.button?.effectiveAppearance.name.rawValue ?? ""
        let cacheKey = "ax-warning|\(appearance)"
        let image: NSImage
        if let cached = iconCache[cacheKey] {
            image = cached
        } else {
            guard let symbol = NSImage(
                systemSymbolName: MenuBarTitleComposer.accessibilityWarningSymbolName,
                accessibilityDescription: Strings.accessibilityWarningBadge()
            )?.withSymbolConfiguration(NSImage.SymbolConfiguration(
                pointSize: max(NSFont.smallSystemFontSize, NSFont.systemFontSize - 2),
                weight: .regular,
                scale: .small
            )) else {
                return NSAttributedString(string: "!", attributes: baseAttributes(color: color))
            }

            image = symbol.tinted(with: color)
            iconCache[cacheKey] = image
        }

        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(x: 0, y: -2, width: image.size.width, height: image.size.height)

        return NSAttributedString(attachment: attachment)
    }

    private func iconCacheKey(for metric: MenuBarMetric) -> String {
        // Icons are now severity-independent (always secondary), so the key is just the
        // symbol and appearance. Appearance keeps a light/dark switch re-tinting once
        // instead of baking a stale dynamic color forever.
        let appearance = statusItem.button?.effectiveAppearance.name.rawValue ?? ""
        return "\(metric.symbolName)|\(appearance)"
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        button.target = self
        button.action = #selector(togglePopover(_:))
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.delegate = self
        // No content controller at init: the SwiftUI graph is built per-open and released on
        // close (ADR-001), so nothing observes CPUState's 1 Hz churn while the popover is
        // closed. This makes the idle-CPU render storm structurally impossible while closed.
    }

    /// Builds a fresh popover content controller. Called on every open and released on close,
    /// so the `PopoverView` graph — and its observation of `CPUState` — exists only while the
    /// popover is shown (ADR-001).
    private func makePopoverHostingController() -> NSHostingController<PopoverView> {
        let hostingController = NSHostingController(
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
        // PopoverView fixes its width and sizes its height to content; propagate that
        // intrinsic size so the popover grows/shrinks to fit instead of clipping or
        // leaving a void. Re-applied on every build.
        hostingController.sizingOptions = .preferredContentSize
        return hostingController
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            openPopover()
        }
    }

    /// Opens the popover programmatically (used by the one-time post-update nudge),
    /// running the same pre-show refresh the manual toggle does. A no-op if the
    /// popover is already shown, so the nudge can never toggle an open popover closed.
    func openPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        launchAtLoginSettings.refresh()
        state.refreshAccessibilityAuthorization()
        // Build the SwiftUI graph fresh for this open, after the pre-show refreshes so the
        // first body pass reads current state; popoverDidClose releases it (ADR-001).
        popover.contentViewController = makePopoverHostingController()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    // MARK: - NSPopoverDelegate

    func popoverWillShow(_ notification: Notification) {
        state.isPopoverOpen = true
    }

    func popoverDidClose(_ notification: Notification) {
        state.isPopoverOpen = false
        // Release the SwiftUI graph so nothing observes CPUState's 1 Hz churn while closed
        // (ADR-001). Rebuilt fresh on the next open by makePopoverHostingController().
        popover.contentViewController = nil
    }
}

private enum MenuBarMetric {
    case cpu
    case ram
    case network
    case temperature
    case disk
    case tokens

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
        case .disk:
            return "DISK"
        case .tokens:
            return TokenFormatter.menuBarLabel
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
        case .disk:
            return "circle.fill"
        case .tokens:
            return "number"
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
        case .disk:
            return Strings.disk()
        case .tokens:
            return Strings.tokens()
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
