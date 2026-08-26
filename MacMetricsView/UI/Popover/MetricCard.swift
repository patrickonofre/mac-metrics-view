import SwiftUI

/// Pure, SwiftUI-free accessibility-string composition for a metric card. Kept out
/// of the view so the label/severity/expand wording is unit-testable (ADR-005).
enum MetricCardAccessibility {
    /// "<title>, <value>" with a severity suffix appended only when not `.normal`.
    static func label(
        title: String,
        value: String,
        severity: CPUMenuBarTextStyle,
        _ language: AppLanguage = .current
    ) -> String {
        "\(title), \(value)\(severitySuffix(severity, language))"
    }

    /// ", Elevated" / ", High" for non-normal severities; empty for `.normal`.
    static func severitySuffix(_ severity: CPUMenuBarTextStyle, _ language: AppLanguage = .current) -> String {
        switch severity {
        case .normal: return ""
        case .elevatedCPU: return ", \(Strings.severityElevated(language))"
        case .highCPU: return ", \(Strings.severityHigh(language))"
        }
    }

    /// Action word for the expand/collapse affordance, reflecting current state.
    static func expansionLabel(isExpanded: Bool, _ language: AppLanguage = .current) -> String {
        isExpanded ? Strings.cardCollapse(language) : Strings.cardExpand(language)
    }
}

/// One metric rendered as a card: header (icon + title), prominent value, sparkline,
/// and severity color. Detail-heavy kinds (such as Battery) reveal an inline
/// `expanded` region when `isExpanded` — summary-only kinds ignore the binding and
/// show no expand affordance. Replaces the flat `MetricRow` of the old popover.
struct MetricCard<Expanded: View>: View {
    let kind: MetricCardKind
    let symbol: String
    let title: String
    let value: String
    let sparkline: [Double]
    let severity: CPUMenuBarTextStyle
    @Binding var isExpanded: Bool
    @ViewBuilder var expanded: () -> Expanded

    @Environment(\.colorScheme) private var colorScheme

    private var isExpandable: Bool { PopoverTabPresentation.isExpandable(kind) }
    private var showsExpanded: Bool { isExpandable && isExpanded }

    /// Fixed summary height so every card is the same size regardless of its data
    /// (value length, presence of a sparkline). Only the expanded region grows.
    private let summaryHeight: CGFloat = 66

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            summary

            if showsExpanded {
                Divider()
                expanded()
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .contentShape(Rectangle())
        .modifier(ExpandTapModifier(isExpandable: isExpandable, isExpanded: $isExpanded))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(MetricCardAccessibility.label(title: title, value: value, severity: severity))
        .modifier(ExpandAccessibilityModifier(isExpandable: isExpandable, isExpanded: isExpanded))
    }

    /// Fixed-height summary: header (top), prominent value, sparkline anchored to the
    /// bottom. The sparkline slot is always reserved so cards without a trend line
    /// (e.g. Battery) match the others' height.
    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            sparklineSlot
        }
        .frame(height: summaryHeight, alignment: .topLeading)
    }

    private var sparklineSlot: some View {
        Group {
            if sparkline.isEmpty {
                Color.clear
            } else {
                SparklineView(values: sparkline, height: 18)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(height: 18)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .imageScale(.small)
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .center)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 4)

            if isExpandable {
                Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                    .imageScale(.medium)
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    /// Resolved through the shared `SeverityPalette` so the card value reads identically
    /// to the menu bar for every severity (ADR-001, ADR-002).
    private var valueColor: Color {
        let appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua) ?? .currentDrawing()
        let nsColor = SeverityPalette.default.color(
            role: PopoverTabPresentation.colorRole(for: severity),
            accent: .controlAccentColor,
            appearance: appearance
        )
        return Color(nsColor: nsColor)
    }
}

/// Adds the whole-card tap toggle only for expandable cards; the binding write is
/// wrapped in `withAnimation` so the grid reflow (ADR-004) animates.
private struct ExpandTapModifier: ViewModifier {
    let isExpandable: Bool
    @Binding var isExpanded: Bool

    func body(content: Content) -> some View {
        if isExpandable {
            content.onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }
        } else {
            content
        }
    }
}

/// Adds button trait + expand/collapse accessibility label only for expandable cards.
private struct ExpandAccessibilityModifier: ViewModifier {
    let isExpandable: Bool
    let isExpanded: Bool

    func body(content: Content) -> some View {
        if isExpandable {
            content
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(MetricCardAccessibility.expansionLabel(isExpanded: isExpanded))
        } else {
            content
        }
    }
}
