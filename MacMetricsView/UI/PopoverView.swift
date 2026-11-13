import AppKit
import SwiftUI

/// Thin tabbed shell for the redesigned popover (ADR-001): pinned banners, a
/// Metrics/Settings/Actions segmented control, and the selected tab's body. All
/// metric/config/action content lives in the per-tab views under `UI/Popover/`.
/// The coordinator tracks the selected tab for sampling. Expansion stays ephemeral
/// `@State` (ADR-002). The popover reopens on Metrics with cards collapsed.
struct PopoverView: View {
    @ObservedObject var state: CPUState
    /// Observed separately from `state` (task-004): the recovery banner and the 1Hz
    /// lock countdown have no AppKit-imperative refresh path, so this view reacts
    /// to `CleaningLockModel`'s own publisher directly (which itself bridges its nested
    /// `AccessibilityRecoveryModel` — see the comment on `CleaningLockModel`).
    @ObservedObject var lock: CleaningLockModel
    @ObservedObject var launchAtLoginSettings: LaunchAtLoginSettings
    let dismissPopover: () -> Void
    let quit: () -> Void

    @State private var expandedCards: Set<MetricCardKind> = PopoverView.captureSeededExpandedCards()

    private let popoverWidth: CGFloat = 380

    /// Capture-mode only (MMV_CAPTURE_CARD, dev tool): pre-expand the named metric cards
    /// so the marketing screenshots can show each card's detail. Empty in normal use.
    private static func captureSeededExpandedCards() -> Set<MetricCardKind> {
        guard let raw = ProcessInfo.processInfo.environment["MMV_CAPTURE_CARD"] else { return [] }
        let map: [String: MetricCardKind] = [
            "cpu": .cpu, "gpu": .gpu, "ram": .ram, "network": .network,
            "temperature": .temperature, "disk": .disk, "battery": .battery,
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
            VStack(alignment: .leading, spacing: 10) {
                headerBar

                // Critical banners pinned above the tab bar so they show on every tab.
                if !Self.isCaptureMode,
                   UpdateBannerPresentation.showsBanner(availableVersion: state.availableUpdateVersion) {
                    UpdateBanner(availableVersion: state.availableUpdateVersion ?? "") {
                        state.checkForUpdates()
                    }
                }

                if !Self.isCaptureMode,
                   CleaningRecoveryPresentation.showsRecoveryBanner(
                       isEnabled: lock.settings.isEnabled,
                       isAccessibilityGranted: lock.recovery.isGranted
                   ) {
                    RecoveryBanner(wasResetByUpdate: lock.recovery.resetByUpdate)
                }

                tabBar

                tabBody

            }
            .controlSize(.small)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(width: popoverWidth, alignment: .topLeading)
            .onAppear {
                state.refreshAccessibilityAuthorization()
            }
            .onChange(of: state.isMetricsTabVisible && expandedCards.contains(.cpu), initial: true) { _, visible in
                if visible {
                    state.metrics.beginProcessSampling()
                } else {
                    state.metrics.endProcessSampling()
                }
            }
            .onDisappear {
                // If the popover is dismissed mid-recovery, stop the probe poll loop.
                // No-op unless we were awaiting a grant.
                lock.recovery.cancelRecovery()
            }
        } else {
            Color.clear
                .frame(width: 1, height: 1)
        }
    }

    private var headerBar: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Mac Metrics View")
                .font(.headline)

            Text(Strings.appVersion())
                .font(.caption2)
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
        Picker("", selection: $state.selectedPopoverTab) {
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
        switch state.selectedPopoverTab {
        case .metrics:
            MetricsTab(metrics: state.metrics, expandedCards: $expandedCards)
        case .settings:
            SettingsTab(metrics: state.metrics, launchAtLoginSettings: launchAtLoginSettings)
        case .actions:
            ActionsTab(
                state: state,
                lock: lock,
                keepAwake: state.keepAwake,
                dismissPopover: dismissPopover
            )
        }
    }
}
