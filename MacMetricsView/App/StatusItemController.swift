import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let state: CPUState
    private let launchAtLoginSettings: LaunchAtLoginSettings
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    // Template SF Symbols are appearance- and background-independent (the system tints
    // them at draw time), so caching by symbol name alone is enough to keep the per-tick
    // title rebuild from re-rendering images.
    private var iconCache: [String: NSImage] = [:]
    private var titleUpdateScheduled = false
    /// Signature of the last title actually applied to the button (PERF-02). Recomposed each
    /// tick from the freshly built attributed string + effective appearance; when it matches,
    /// the assignment to `button.attributedTitle` is skipped, so a steady state (e.g. CPU flat,
    /// RAM in whole GB) no longer relayouts the status bar or wakes the WindowServer every tick.
    private var lastTitleSignature: String?
    /// The monospaced menu-bar font is size-fixed at runtime, so it is resolved once instead of
    /// per segment per tick (PERF-02 rider). Appearance-independent; no invalidation needed.
    private lazy var monospacedFont: NSFont = NSFont.monospacedSystemFont(
        ofSize: max(NSFont.smallSystemFontSize, NSFont.systemFontSize - 2),
        weight: .regular
    )
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

        state.$availableUpdateVersion
            .removeDuplicates()
            .sink { [weak self] _ in self?.setNeedsTitleUpdate() }
            .store(in: &cancellables)

        // The value color now follows the system accent and is resolved per appearance
        // (ADR-001), so neither change is carried by a metric tick. Re-render immediately
        // on either signal instead of trailing the next sample (ADR-003). The icon cache
        // keys on appearance, so a light/dark flip also needs the rebuild to re-tint.
        NotificationCenter.default
            .publisher(for: NSColor.systemColorsDidChangeNotification)
            .sink { [weak self] _ in self?.setNeedsTitleUpdate() }
            .store(in: &cancellables)

        // Re-tint on a real light↔dark flip. Observe the *application's* effective
        // appearance, not the status-button's: AppKit briefly swaps the button into a
        // template/vibrant appearance every time it snapshots the menu-bar replicant
        // (`setSnapshotImage:needsInactiveTemplateStyling:`), so the button's KVO emits
        // a constant A→B→A→B flicker. Mapping to a stable light/dark `Bool` and
        // de-duping collapses that flicker — observing it directly (even deduped by
        // name) re-entered updateTitle → snapshot → emit → updateTitle and pinned a core.
        NSApplication.shared.publisher(for: \.effectiveAppearance)
            .map { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
            .removeDuplicates()
            .dropFirst()
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

        if state.metrics.visibility.showCPU {
            attributedTitle.append(statusSegment(
                metric: .cpu,
                value: CPUFormatter.fixedWidthPercentageString(state.metrics.latestSample?.totalUsagePercent),
                style: state.metrics.menuBarTextStyle
            ))
        }

        if state.metrics.visibility.showGPU {
            if attributedTitle.length > 0 {
                attributedTitle.append(separator)
            }

            attributedTitle.append(statusSegment(
                metric: .gpu,
                value: GPUFormatter.menuBarTitle(for: state.metrics.latestGPUSample, showLabel: false),
                style: state.metrics.gpuMenuBarTextStyle
            ))
        }

        if state.metrics.visibility.showRAM {
            if attributedTitle.length > 0 {
                attributedTitle.append(separator)
            }

            attributedTitle.append(statusSegment(
                metric: .ram,
                value: RAMFormatter.valueString(for: state.metrics.latestRAMSample),
                style: state.metrics.ramMenuBarTextStyle
            ))
        }

        if state.metrics.visibility.showNetwork {
            if attributedTitle.length > 0 {
                attributedTitle.append(separator)
            }

            attributedTitle.append(statusSegment(
                metric: .network,
                value: NetworkFormatter.compactMenuBarValue(for: state.metrics.latestNetworkSample),
                style: .normal
            ))
        }

        if state.metrics.visibility.showTemperature {
            if attributedTitle.length > 0 {
                attributedTitle.append(separator)
            }

            attributedTitle.append(statusSegment(
                metric: .temperature,
                value: TemperatureFormatter.displayString(for: state.metrics.latestTemperatureSample),
                style: state.metrics.temperatureMenuBarTextStyle
            ))
        }

        if state.metrics.visibility.showDisk {
            if attributedTitle.length > 0 {
                attributedTitle.append(separator)
            }

            attributedTitle.append(statusSegment(
                metric: .disk,
                value: DiskFormatter.stableMenuBarTitle(
                    for: state.metrics.latestDiskSample,
                    metric: state.metrics.diskMenuBarMetric,
                    showLabel: false
                ),
                style: state.metrics.diskMenuBarTextStyle
            ))
        }

        // Battery emits only when present (sample non-nil), so a desktop Mac shows nothing
        // even with the toggle on (ADR-003). The icon is the live charge-level glyph.
        if state.metrics.visibility.showBattery, state.metrics.latestBatterySample != nil {
            if attributedTitle.length > 0 {
                attributedTitle.append(separator)
            }

            attributedTitle.append(statusSegment(
                metric: .battery,
                value: BatteryFormatter.menuBarValue(for: state.metrics.latestBatterySample),
                style: state.metrics.batteryMenuBarTextStyle,
                symbolOverride: BatteryFormatter.menuBarGlyphName(for: state.metrics.latestBatterySample)
            ))
        }

        if attributedTitle.length == 0 {
            attributedTitle.append(NSAttributedString(
                string: Strings.metricsPlaceholder(),
                attributes: baseAttributes(color: .labelColor)
            ))
        }

        // Additive, secondary update badge while a newer version is available —
        // never recolors the metric segments (ADR-003). The accessibility-permission
        // warning lives only in the popover's recovery banner now, not the menu bar.
        if MenuBarTitleComposer.showsUpdateBadge(availableVersion: state.availableUpdateVersion) {
            attributedTitle.append(separator)
            attributedTitle.append(updateBadgeGlyphAttachment(color: .labelColor))
        }

        // Dirty-check (PERF-02): only touch the button when the rendered result actually
        // changed. The signature is derived from the composed string, its per-run foreground
        // colors and attachment-image identities, plus the effective appearance — so any real
        // change (value, severity, glyph bucket, badge, light↔dark flip) reapplies, while an
        // identical tick is a no-op. `NSAttributedString.isEqual` can't be used here: the icon
        // and badge attachments are new instances each rebuild and never compare equal.
        let signature = Self.renderSignature(for: attributedTitle, isDark: Self.isDarkAppearance)
        guard signature != lastTitleSignature else { return }
        lastTitleSignature = signature

        button.attributedTitle = attributedTitle
        button.setAccessibilityLabel(state.accessibilityMenuBarTitle)
    }

    /// A stable, drift-free fingerprint of the *rendered* title. Reads the actual composed
    /// output (not a parallel recomposition of the inputs), so it cannot fall out of sync with
    /// `updateTitle`. Cached glyph images have stable identities across ticks (same symbol →
    /// same cached `NSImage`), so an unchanged icon does not perturb the signature, while a
    /// battery charge-bucket swap (new cache key → new image) does.
    private static func renderSignature(for title: NSAttributedString, isDark: Bool) -> String {
        let full = NSRange(location: 0, length: title.length)
        var parts: [String] = [title.string, isDark ? "d" : "l"]
        title.enumerateAttribute(.foregroundColor, in: full) { value, range, _ in
            if let color = value as? NSColor {
                parts.append("c\(range.location):\(color.description)")
            }
        }
        title.enumerateAttribute(.attachment, in: full) { value, range, _ in
            if let attachment = value as? NSTextAttachment, let image = attachment.image {
                parts.append("a\(range.location):\(ObjectIdentifier(image).hashValue)")
            }
        }
        return parts.joined(separator: "|")
    }

    /// Whether the app's effective appearance is dark. Menu-bar template glyphs and dynamic
    /// colors re-tint at draw time, but the signature includes this so a light↔dark flip still
    /// forces one reapplication (the observer that drives it exists for exactly that re-tint).
    private static var isDarkAppearance: Bool {
        NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    private func statusSegment(
        metric: MenuBarMetric,
        value: String,
        style: CPUMenuBarTextStyle,
        labelOverride: String? = nil,
        symbolOverride: String? = nil
    ) -> NSAttributedString {
        // Only the value carries severity color, never the identifier. Both identifier
        // styles render in the value's foreground tone — the icon as a full-strength
        // template, the text label in `labelColor` — so every segment is one uniform
        // color, light or dark, with no dimmed glyph competing for attention.
        let valueColor = color(for: style)
        let identifierColor = NSColor.labelColor
        let segment = NSMutableAttributedString()

        switch state.metrics.display.identifierStyle {
        case .labels:
            segment.append(NSAttributedString(
                string: "\(labelOverride ?? metric.label) ",
                attributes: baseAttributes(color: identifierColor)
            ))
        case .icons:
            segment.append(iconAttachment(for: metric, color: identifierColor, symbolOverride: symbolOverride))
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
            .font: monospacedFont,
            .foregroundColor: color
        ]
    }

    /// Resolves the value color through `SeverityPalette.menuBarColor`: monochrome
    /// `labelColor` for normal/elevated and red only for critical, for an Apple-native
    /// menu bar (ADR-001, ADR-002). No accent or appearance read — `labelColor` adapts to
    /// the menu bar at draw time. The popover keeps the colored `color(role:accent:...)`.
    private func color(for style: CPUMenuBarTextStyle) -> NSColor {
        SeverityPalette.default.menuBarColor(role: PopoverTabPresentation.colorRole(for: style))
    }

    private func iconAttachment(for metric: MenuBarMetric, color: NSColor, symbolOverride: String? = nil) -> NSAttributedString {
        let symbolName = symbolOverride ?? metric.symbolName
        let cacheKey = iconCacheKey(for: metric, symbolOverride: symbolOverride)
        let image: NSImage
        if let cached = iconCache[cacheKey] {
            image = cached
        } else {
            guard let symbol = NSImage(
                systemSymbolName: symbolName,
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

            image = symbol.menuBarTemplate()
            iconCache[cacheKey] = image
        }

        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(x: 0, y: -2, width: image.size.width, height: image.size.height)

        return NSAttributedString(attachment: attachment)
    }

    /// The secondary update badge glyph appended to the title while a newer version
    /// is available. Cached per appearance like the warning glyph, so the per-tick
    /// title rebuild does not re-render it.
    private func updateBadgeGlyphAttachment(color: NSColor) -> NSAttributedString {
        let cacheKey = "update-badge"
        let image: NSImage
        if let cached = iconCache[cacheKey] {
            image = cached
        } else {
            guard let symbol = NSImage(
                systemSymbolName: MenuBarTitleComposer.updateBadgeSymbolName,
                accessibilityDescription: nil
            )?.withSymbolConfiguration(NSImage.SymbolConfiguration(
                pointSize: max(NSFont.smallSystemFontSize, NSFont.systemFontSize - 2),
                weight: .regular,
                scale: .small
            )) else {
                return NSAttributedString(string: "↓", attributes: baseAttributes(color: color))
            }

            image = symbol.menuBarTemplate()
            iconCache[cacheKey] = image
        }

        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(x: 0, y: -2, width: image.size.width, height: image.size.height)

        return NSAttributedString(attachment: attachment)
    }

    private func iconCacheKey(for metric: MenuBarMetric, symbolOverride: String? = nil) -> String {
        // Icons are now severity- and appearance-independent: a template glyph is tinted
        // by the menu bar at draw time, so a light/dark flip re-tints the same cached
        // image without a rebuild. The key is just the symbol; the override (e.g. the
        // battery charge-level glyph) is part of it so each charge bucket caches separately.
        symbolOverride ?? metric.symbolName
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        button.target = self
        button.action = #selector(togglePopover(_:))
    }

    private func configurePopover() {
        // Capture mode (MMV_CAPTURE=1, dev-only): keep the popover open when it loses
        // focus so an external screenshot tool can grab each tab. Inert otherwise.
        popover.behavior =
            ProcessInfo.processInfo.environment["MMV_CAPTURE"] == "1" ? .applicationDefined : .transient
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
                ambient: state.ambient,
                lock: state.lock,
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
        // One-shot battery read so the popover row is live even when the segment is hidden
        // and the continuous sampler is gated off (ADR-003). No-op cost on desktops.
        state.metrics.refreshBatteryReading()
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

    func popoverDidShow(_ notification: Notification) {
        // Capture mode (dev-only): the popover window now exists, so emit its id for an
        // external screenshot tool to grab exactly this window (`screencapture -l<id>`),
        // regardless of z-order. Inert in normal use.
        guard ProcessInfo.processInfo.environment["MMV_CAPTURE"] == "1" else { return }
        if let number = popover.contentViewController?.view.window?.windowNumber {
            FileHandle.standardError.write(Data("MMV_POPOVER_WINDOW=\(number)\n".utf8))
        }
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
    case battery
    case gpu

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
        case .battery:
            return "BAT"
        case .gpu:
            return "GPU"
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
        case .battery:
            // Static fallback; the live segment passes a charge-level glyph override.
            return "battery.100"
        case .gpu:
            // No official `gpu` SF Symbol on macOS 14; this 3D-stack proxy reads as
            // graphics/compute. iconAttachment falls back to the "GPU" label if absent.
            return "square.stack.3d.up"
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
        case .battery:
            return Strings.battery()
        case .gpu:
            return Strings.gpu()
        }
    }
}

private extension NSImage {
    /// Marks the glyph as a *template* and returns it. `isTemplate = true` is what fixes
    /// icons vanishing on some backgrounds: the menu bar tints a template with its live
    /// foreground material, so the glyph adapts to any wallpaper/translucency and inverts
    /// under the selection highlight (popover open) — exactly like the `labelColor` value
    /// text. The old path baked a frozen color with `isTemplate = false`, which got
    /// neither treatment and washed out on bright or highlighted bars.
    ///
    /// Returns the vector symbol itself — it is NOT pre-rasterized into a bitmap. The
    /// status button rasterizes it at device resolution, so the glyph stays crisp and
    /// renders in the same full-strength tone as the value. Pre-rasterizing here (an
    /// `NSImage` + `lockFocus` at the main screen's 1x backing) softened the edges into a
    /// grayer glyph that read as a different color from the device-resolution text.
    func menuBarTemplate() -> NSImage {
        isTemplate = true
        return self
    }
}
