import AppKit
import SwiftUI

/// Thin tabbed shell for the redesigned popover (ADR-001): pinned banners, a
/// Metrics/Settings/Actions segmented control, and the selected tab's body. All
/// metric/config/action content lives in the per-tab views under `UI/Popover/`.
/// Transient tab/expansion state is ephemeral `@State` (ADR-002) — the popover always
/// reopens on Metrics with cards collapsed because `StatusItemController` rebuilds
/// this view on every open.
struct PopoverView: View {
    @ObservedObject var state: CPUState
    /// Observed separately from `state` (task-003): the theme-suggestion banner has no
    /// AppKit-imperative refresh path (unlike the menu bar), so it must react to
    /// `AmbientThemeModel`'s own publisher directly to stay live within an open popover.
    @ObservedObject var ambient: AmbientThemeModel
    /// Observed separately from `state` (task-004): the recovery banner and the 1Hz
    /// lock countdown have no AppKit-imperative refresh path either, so this view reacts
    /// to `CleaningLockModel`'s own publisher directly (which itself bridges its nested
    /// `AccessibilityRecoveryModel` — see the comment on `CleaningLockModel`).
    @ObservedObject var lock: CleaningLockModel
    @ObservedObject var launchAtLoginSettings: LaunchAtLoginSettings
    let dismissPopover: () -> Void
    let quit: () -> Void

    @State private var selectedTab: PopoverTab = .metrics
    @State private var expandedCards: Set<MetricCardKind> = PopoverView.captureSeededExpandedCards()

    private let popoverWidth: CGFloat = 380

    /// Capture-mode only (MMV_CAPTURE_CARD, dev tool): pre-expand the named metric cards
    /// so the marketing screenshots can show each card's detail. Empty in normal use.
    private static func captureSeededExpandedCards() -> Set<MetricCardKind> {
        guard let raw = ProcessInfo.processInfo.environment["MMV_CAPTURE_CARD"] else { return [] }
        let map: [String: MetricCardKind] = [
            "cpu": .cpu, "gpu": .gpu, "ram": .ram, "network": .network,
            "temperature": .temperature, "disk": .disk, "battery": .battery, "tokens": .tokens,
        ]
        return Set(raw.split(separator: ",").compactMap { map[$0.trimmingCharacters(in: .whitespaces)] })
    }

    /// Capture-mode flag (MMV_CAPTURE=1, dev tool): used to hide transient banners so the
    /// marketing screenshots show a clean popover.
    private static var isCaptureMode: Bool {
        ProcessInfo.processInfo.environment["MMV_CAPTURE"] == "1"
    }

    var body: some View {
        // Defense-in-depth (ADR-002): StatusItemController tears down the popover hosting
        // controller while closed (ADR-001), so normally this view is not even instantiated
        // when the popover is shut. This gate is the second, independent layer — if a future
        // change ever hosts this view while the popover is closed, the body stays inert
        // instead of re-rendering on CPUState's 1 Hz churn. Do not remove without revisiting
        // ADR-001/ADR-002.
        if state.isPopoverOpen {
            // Content-driven height: the header, pinned banners, tab bar, and the selected
            // tab's body each take exactly the room they need, top to bottom. The popover
            // resizes to fit; nothing scrolls. Width is fixed (sizing contract with
            // StatusItemController).
            VStack(alignment: .leading, spacing: 12) {
                headerBar

                // Critical banners pinned above the tab bar so they show on every tab.
                if !Self.isCaptureMode,
                   UpdateBannerPresentation.showsBanner(availableVersion: state.availableUpdateVersion) {
                    UpdateBanner(availableVersion: state.availableUpdateVersion ?? "") {
                        state.checkForUpdates()
                    }
                }

                if !Self.isCaptureMode,
                   CleaningRecoveryPresentation.showsRecoveryBanner(isAccessibilityGranted: lock.recovery.isGranted) {
                    RecoveryBanner(wasResetByUpdate: lock.recovery.resetByUpdate)
                }

                let ambientBanner = AmbientSuggestionPresentation.bannerState(
                    suggestion: ambient.suggestion,
                    lastApply: ambient.lastApplyResult
                )
                if !Self.isCaptureMode, ambientBanner != .hidden {
                    AmbientSuggestionBanner(
                        state: ambientBanner,
                        apply: { ambient.apply() },
                        dismiss: { ambient.dismiss() }
                    )
                }

                tabBar

                tabBody

                Text(Strings.developedBy())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .controlSize(.small)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(width: popoverWidth, alignment: .topLeading)
            .onAppear {
                lock.recovery.refreshAuthorization()
                // Time-derived token figures (burn rate, rolling windows) refresh on a
                // ~30s timer only while the popover is open (ADR-005).
                state.beginTokenAutoRefresh()
                state.metrics.beginProcessSampling()
            }
            .onDisappear {
                // If the popover is dismissed mid-recovery, stop the probe poll loop.
                // No-op unless we were awaiting a grant.
                lock.recovery.cancelRecovery()
                state.endTokenAutoRefresh()
                state.metrics.endProcessSampling()
            }
        } else {
            Color.clear
                .frame(width: 1, height: 1)
        }
    }

    private var headerBar: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Mac Metrics View")
                .font(.callout.weight(.semibold))

            Text(Strings.appVersion())
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button(Strings.quit(), action: quit)
                .font(.caption)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var tabBar: some View {
        Picker("", selection: $selectedTab) {
            ForEach(PopoverTabPresentation.tabs, id: \.self) { tab in
                Text(PopoverTabPresentation.title(tab)).tag(tab)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var tabBody: some View {
        switch selectedTab {
        case .metrics:
            MetricsTab(metrics: state.metrics, token: state.token, expandedCards: $expandedCards)
        case .settings:
            SettingsTab(state: state, metrics: state.metrics, launchAtLoginSettings: launchAtLoginSettings)
        case .actions:
            ActionsTab(
                state: state,
                lock: lock,
                dismissPopover: dismissPopover
            )
        }
    }
}
