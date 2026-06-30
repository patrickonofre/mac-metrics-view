import SwiftUI

/// Pure, SwiftUI-free trend derivations for the metric cards: throughput
/// normalization and RAM series selection. Kept testable (ADR-005).
enum MetricTrend {
    /// Scales a throughput series so its peak maps to 100. Empty input stays empty;
    /// an all-zero series is returned unchanged (no division by zero).
    static func normalized(_ rates: [Double]) -> [Double] {
        guard let maxRate = rates.max(), maxRate > 0 else { return rates }
        return rates.map { $0 / maxRate * 100 }
    }

    /// The RAM sparkline series matching the selected menu-bar metric.
    static func ramSeries(
        metric: MetricDisplaySettings.RAMMenuBarMetric,
        pressure: [Double],
        appMemory: [Double],
        usedTotal: [Double]
    ) -> [Double] {
        switch metric {
        case .usedTotal: return usedTotal
        case .pressure: return pressure
        case .appMemory: return appMemory
        }
    }
}

/// Pure row-packing for the two-column metric grid: an expanded card takes its own
/// full-width row; summary cards pair two-per-row in `cardOrder`. Testable (ADR-004).
enum MetricGridLayout {
    static func rows(order: [MetricCardKind], expanded: Set<MetricCardKind>) -> [[MetricCardKind]] {
        var rows: [[MetricCardKind]] = []
        var pending: MetricCardKind?

        for kind in order {
            if expanded.contains(kind) {
                if let p = pending { rows.append([p]); pending = nil }
                rows.append([kind])
            } else if let p = pending {
                rows.append([p, kind]); pending = nil
            } else {
                pending = kind
            }
        }

        if let p = pending { rows.append([p]) }
        return rows
    }
}

/// Metrics tab body: the seven metric cards in a two-column `Grid`, ordered by
/// `PopoverTabPresentation.cardOrder`. Expandable cards (Tokens, Battery) span both
/// columns when their kind is in the bound `expandedCards` set (ADR-004); expansion
/// state is ephemeral and owned by the shell (ADR-002). Read-only — no settings here.
struct MetricsTab: View {
    @ObservedObject var state: CPUState
    /// Observed separately from `state` (task-002): the Dev/AI pillar's popover-open
    /// 30s refresh (ADR-005) mutates only this object, so isolating the observation here
    /// keeps that tick from re-rendering the rest of the metrics grid.
    @ObservedObject var token: TokenUsageModel
    @Binding var expandedCards: Set<MetricCardKind>

    private var layoutRows: [[MetricCardKind]] {
        MetricGridLayout.rows(order: PopoverTabPresentation.cardOrder, expanded: expandedCards)
    }

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(Array(layoutRows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(row, id: \.self) { kind in
                        card(for: kind)
                            .gridCellColumns(row.count == 1 && expandedCards.contains(kind) ? 2 : 1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func expansionBinding(for kind: MetricCardKind) -> Binding<Bool> {
        Binding(
            get: { expandedCards.contains(kind) },
            set: { isOn in
                if isOn { expandedCards.insert(kind) } else { expandedCards.remove(kind) }
            }
        )
    }

    @ViewBuilder
    private func card(for kind: MetricCardKind) -> some View {
        switch kind {
        case .cpu:
            MetricCard(
                kind: .cpu,
                symbol: "cpu",
                title: "CPU",
                value: CPUFormatter.percentageString(state.latestSample?.totalUsagePercent),
                sparkline: state.history.samples.map(\.totalUsagePercent),
                severity: state.menuBarTextStyle,
                isExpanded: expansionBinding(for: .cpu)
            ) {
                cpuDetail
            }

        case .gpu:
            MetricCard(
                kind: .gpu,
                symbol: "square.stack.3d.up",
                title: Strings.gpu(),
                value: state.gpuCardValue,
                sparkline: state.gpuHistory.samples.map(\.utilizationPercent),
                severity: state.gpuMenuBarTextStyle,
                isExpanded: expansionBinding(for: .gpu)
            ) { EmptyView() }

        case .ram:
            MetricCard(
                kind: .ram,
                symbol: "memorychip",
                title: "RAM",
                value: state.ramCardValue,
                sparkline: MetricTrend.ramSeries(
                    metric: state.ramMenuBarMetric,
                    pressure: state.ramHistory.samples.map(\.pressurePercent),
                    appMemory: state.ramHistory.samples.map(\.appMemoryPercent),
                    usedTotal: state.ramHistory.samples.map(\.usedPercent)
                ),
                severity: state.ramMenuBarTextStyle,
                isExpanded: expansionBinding(for: .ram)
            ) {
                ramDetail
            }

        case .network:
            MetricCard(
                kind: .network,
                symbol: "network",
                title: Strings.network(),
                value: networkSummary,
                sparkline: MetricTrend.normalized(state.networkHistory.samples.map(\.totalBytesPerSecond)),
                severity: .normal,
                isExpanded: expansionBinding(for: .network)
            ) {
                networkDetail
            }

        case .temperature:
            MetricCard(
                kind: .temperature,
                symbol: "thermometer",
                title: Strings.temperature(),
                value: TemperatureFormatter.displayString(for: state.latestTemperatureSample),
                sparkline: state.temperatureHistory.samples.map(\.trendValue),
                severity: state.temperatureMenuBarTextStyle,
                isExpanded: expansionBinding(for: .temperature)
            ) { EmptyView() }

        case .disk:
            MetricCard(
                kind: .disk,
                symbol: "internaldrive",
                title: Strings.disk(),
                value: DiskFormatter.menuBarTitle(
                    for: state.latestDiskSample,
                    metric: state.diskMenuBarMetric,
                    showLabel: false
                ),
                sparkline: MetricTrend.normalized(state.diskHistory.samples.map(\.totalBytesPerSecond)),
                severity: state.diskMenuBarTextStyle,
                isExpanded: expansionBinding(for: .disk)
            ) {
                diskDetail
            }

        case .battery:
            MetricCard(
                kind: .battery,
                symbol: state.batterySymbolName,
                title: Strings.battery(),
                value: state.batteryRowValue,
                sparkline: [],
                severity: state.batteryMenuBarTextStyle,
                isExpanded: expansionBinding(for: .battery)
            ) {
                batteryDetail
            }

        case .tokens:
            MetricCard(
                kind: .tokens,
                symbol: "number",
                title: Strings.tokens(),
                value: token.rowValue,
                sparkline: token.sparkline,
                severity: .normal,
                isExpanded: expansionBinding(for: .tokens)
            ) {
                tokenDetail
            }
        }
    }

    // MARK: - Expanded detail content

    @ViewBuilder
    private var cpuDetail: some View {
        if state.topCPUProcesses.isEmpty {
            Text(Strings.cpuSampling())
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            TopProcessRow(processes: state.topCPUProcesses)
        }
    }

    @ViewBuilder
    private var ramDetail: some View {
        if state.ramDetailRows.isEmpty {
            Text(Strings.cpuSampling())
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            RAMDetailRow(details: state.ramDetailRows)
        }
    }

    @ViewBuilder
    private var batteryDetail: some View {
        if state.batteryDetailRows.isEmpty {
            Text(Strings.batteryNoBattery())
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            BatteryDetailRow(details: state.batteryDetailRows)
        }
    }

    @ViewBuilder
    private var tokenDetail: some View {
        VStack(alignment: .leading, spacing: 4) {
            if token.isEmpty {
                Text(Strings.tokenEmptyState())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                TokenBreakdownRow(breakdown: token.breakdown)
            }

            if let totalCost = token.costRowValue {
                TokenCostRow(
                    total: totalCost,
                    perModel: token.costPerModel,
                    showsUnpricedNote: token.costHasUnpricedTokens
                )
            }

            if let pace = token.paceRowValue {
                TokenPaceRow(value: pace)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var networkDetail: some View {
        NetworkDetailRow(details: state.networkDetailRows)
    }

    @ViewBuilder
    private var diskDetail: some View {
        DiskDetailRow(details: state.diskDetailRows)
    }

    private var networkSummary: String {
        "↓ \(NetworkFormatter.byteRateString(state.latestNetworkSample?.downloadBytesPerSecond)) ↑ \(NetworkFormatter.byteRateString(state.latestNetworkSample?.uploadBytesPerSecond))"
    }
}

// MARK: - Relocated detail subviews (internal; task_04)

/// List of top CPU consuming processes, shown inside the expanded CPU card.
struct TopProcessRow: View {
    let processes: [ProcessCPUSample]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(processes) { process in
                HStack(spacing: 6) {
                    Text(process.name)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(String(format: "%.1f%%", process.cpuPercent))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .font(.caption2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Activity-Monitor-style memory breakdown, shown inside the expanded RAM card:
/// App Memory, Wired, Compressed, Cached Files, Swap Used, and Pressure.
struct RAMDetailRow: View {
    let details: [(label: String, value: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(details, id: \.label) { item in
                HStack(spacing: 6) {
                    Text(item.label)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(item.value)
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                }
            }
        }
        .font(.caption2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Rolling-window network detail, shown inside the expanded Network card: recent
/// transferred totals and peak rates for download and upload. Same row layout as
/// `RAMDetailRow` (label left, value right) for visual consistency.
struct NetworkDetailRow: View {
    let details: [(label: String, value: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(details, id: \.label) { item in
                HStack(spacing: 6) {
                    Text(item.label)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(item.value)
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                }
            }
        }
        .font(.caption2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Rolling-window disk detail, shown inside the expanded Disk card: recent
/// transferred totals and peak rates for read and write. Same row layout as
/// `NetworkDetailRow` (label left, value right) for visual consistency.
struct DiskDetailRow: View {
    let details: [(label: String, value: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(details, id: \.label) { item in
                HStack(spacing: 6) {
                    Text(item.label)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(item.value)
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                }
            }
        }
        .font(.caption2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Power source / time / health / cycle detail, shown inside the expanded Battery
/// card. Relocated from `PopoverView.swift` (task_04). No sparkline (ADR-002).
struct BatteryDetailRow: View {
    let details: [(label: String, value: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(details, id: \.label) { item in
                HStack(spacing: 3) {
                    Text(item.label)
                        .foregroundStyle(.secondary)
                    Text(item.value)
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                    Spacer(minLength: 0)
                }
            }
        }
        .font(.caption2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Input / output / cache breakdown, shown inside the expanded Tokens card.
/// Relocated from `PopoverView.swift` (task_04).
struct TokenBreakdownRow: View {
    let breakdown: [(label: String, value: String)]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(breakdown, id: \.label) { item in
                HStack(spacing: 3) {
                    Text(item.label)
                        .foregroundStyle(.secondary)
                    Text(item.value)
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                }
            }

            Spacer(minLength: 0)
        }
        .font(.caption2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Estimated USD cost under the token breakdown: headline total, per-model
/// attribution (only when more than one model contributed), and the always-visible
/// "estimated" note. A `≈` prefix plus a footnote flag totals that exclude
/// unrecognized models (ADR-003). Relocated from `PopoverView.swift` (task_04).
struct TokenCostRow: View {
    let total: String
    let perModel: [(label: String, value: String)]
    let showsUnpricedNote: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 12) {
                HStack(spacing: 3) {
                    Text(Strings.tokenCostLabel())
                        .foregroundStyle(.secondary)
                    Text(showsUnpricedNote ? "≈ \(total)" : total)
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                }

                if perModel.count > 1 {
                    ForEach(perModel, id: \.label) { item in
                        HStack(spacing: 3) {
                            Text(item.label)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(item.value)
                                .foregroundStyle(.primary)
                                .monospacedDigit()
                        }
                    }
                }

                Spacer(minLength: 0)
            }

            Text(note)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var note: String {
        showsUnpricedNote
            ? "\(Strings.tokenCostEstimatedNote()) \(Strings.tokenCostUnpricedNote())"
            : Strings.tokenCostEstimatedNote()
    }
}

/// Current pace under the cost row: tokens/hour, cost/hour, and the daily projection
/// (ADR-004). Relocated from `PopoverView.swift` (task_04).
struct TokenPaceRow: View {
    let value: String

    var body: some View {
        HStack(spacing: 3) {
            Text(Strings.tokenPaceLabel())
                .foregroundStyle(.secondary)
            Text(value)
                .foregroundStyle(.primary)
                .monospacedDigit()
            Spacer(minLength: 0)
        }
        .font(.caption2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Strings.tokenPaceLabel()), \(value)")
    }
}

// MARK: - Network helper

private extension NetworkSample {
    var totalBytesPerSecond: Double {
        downloadBytesPerSecond + uploadBytesPerSecond
    }
}
