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

/// One metric rendered as content inside the popover: icon, label, value, sparkline,
/// and optional detail. Detail-heavy kinds reveal an inline region through an explicit
/// button; summary-only kinds ignore the binding and show no expand affordance.
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isExpandable: Bool { PopoverTabPresentation.isExpandable(kind) }
    private var showsExpanded: Bool { isExpandable && isExpanded }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            summary

            if showsExpanded {
                Divider()
                expanded()
                    .padding(.leading, 26)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// Stable metric row: value width is driven by monospaced digits and every metric
    /// reserves a small trend slot, avoiding vertical jitter as samples arrive.
    private var summary: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: symbol)
                .imageScale(.small)
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .center)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                sparklineSlot
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(value)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .layoutPriority(1)

            if isExpandable {
                Button(action: toggleExpansion) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .imageScale(.small)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .help(MetricCardAccessibility.expansionLabel(isExpanded: isExpanded))
                .accessibilityLabel(MetricCardAccessibility.expansionLabel(isExpanded: isExpanded))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(MetricCardAccessibility.label(title: title, value: value, severity: severity))
    }

    private var sparklineSlot: some View {
        Group {
            if sparkline.isEmpty {
                Color.clear
            } else {
                SparklineView(values: sparkline, height: 14)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(height: 14)
    }

    private func toggleExpansion() {
        if reduceMotion {
            isExpanded.toggle()
        } else {
            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded.toggle()
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
