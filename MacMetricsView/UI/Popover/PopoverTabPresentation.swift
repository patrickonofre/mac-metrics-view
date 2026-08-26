import Foundation

/// The three top-level surfaces of the redesigned popover. Display order is fixed
/// by `PopoverTabPresentation.tabs`; the popover always opens on `.metrics`.
enum PopoverTab: CaseIterable, Hashable {
    case metrics
    case settings
    case actions
}

/// One metric rendered as a card in the Metrics grid. Order in the grid is supplied
/// by `PopoverTabPresentation.cardOrder`; expandability by `isExpandable(_:)`.
enum MetricCardKind: Hashable {
    case cpu
    case gpu
    case ram
    case network
    case temperature
    case disk
    case battery
}

/// Semantic color role a metric card uses for its value, derived from the metric's
/// menu-bar severity. SwiftUI-free so the mapping stays unit-testable; views resolve
/// the role to a concrete `Color`.
enum SeverityColorRole: Hashable {
    case normal
    case elevated
    case high
}

/// Pure, SwiftUI/AppKit-free layout decisions for the redesigned popover: the tab
/// list and titles, the default metric-card order, which cards expand, and the
/// severity → color-role mapping. Mirrors the existing `*Presentation` helpers
/// (`UpdateBannerPresentation`, `CleaningRecoveryPresentation`) so the views stay
/// thin and this logic is covered by `PopoverTabPresentationTests` (ADR-005).
enum PopoverTabPresentation {

    /// Tabs in display order. The popover opens on the first (`.metrics`).
    static let tabs: [PopoverTab] = [.metrics, .settings, .actions]

    /// Localized tab title. `.metrics` reuses the existing `metricsPlaceholder`
    /// string; `.settings`/`.actions` use the redesign's new strings.
    static func title(_ tab: PopoverTab, _ language: AppLanguage = .current) -> String {
        switch tab {
        case .metrics: return Strings.metricsPlaceholder(language)
        case .settings: return Strings.settingsTab(language)
        case .actions: return Strings.actionsTab(language)
        }
    }

    /// Default top-to-bottom, left-to-right card order in the Metrics grid.
    static let cardOrder: [MetricCardKind] =
        [.cpu, .gpu, .ram, .network, .temperature, .disk, .battery]

    /// Cards that can expand to double width; all others are summary-only.
    static func isExpandable(_ kind: MetricCardKind) -> Bool {
        kind == .battery || kind == .cpu || kind == .ram || kind == .network || kind == .disk
    }

    /// Maps a metric's menu-bar severity to the card's value color role.
    static func colorRole(for severity: CPUMenuBarTextStyle) -> SeverityColorRole {
        switch severity {
        case .normal: return .normal
        case .elevatedCPU: return .elevated
        case .highCPU: return .high
        }
    }
}
