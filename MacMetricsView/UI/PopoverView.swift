import SwiftUI

struct PopoverView: View {
    @ObservedObject var state: CPUState
    @ObservedObject var launchAtLoginSettings: LaunchAtLoginSettings
    let quit: () -> Void
    private let popoverWidth: CGFloat = 380
    private let popoverHeight: CGFloat = 445

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            appInfoHeader

            Divider()

            MetricVisibilityControls(
                cpuVisible: Binding(
                    get: { state.visibility.showCPU },
                    set: { state.setCPUVisible($0) }
                ),
                ramVisible: Binding(
                    get: { state.visibility.showRAM },
                    set: { state.setRAMVisible($0) }
                ),
                networkVisible: Binding(
                    get: { state.visibility.showNetwork },
                    set: { state.setNetworkVisible($0) }
                ),
                temperatureVisible: Binding(
                    get: { state.visibility.showTemperature },
                    set: { state.setTemperatureVisible($0) }
                ),
                identifierStyle: Binding(
                    get: { state.display.identifierStyle },
                    set: { state.setMetricIdentifierStyle($0) }
                )
            )

            Divider()

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 10) {
                    if state.visibility.showCPU {
                        MetricSection(
                            title: "CPU",
                            value: CPUFormatter.percentageString(state.latestSample?.totalUsagePercent),
                            values: state.history.samples.map(\.totalUsagePercent),
                            severity: state.menuBarTextStyle,
                            details: cpuDetails
                        )
                    }

                    if state.visibility.showRAM {
                        MetricSection(
                            title: "RAM",
                            value: RAMFormatter.usedGBString(state.latestRAMSample?.usedGB),
                            values: state.ramHistory.samples.map(\.usedPercent),
                            severity: state.ramMenuBarTextStyle,
                            details: ramDetails
                        )
                    }

                    if state.visibility.showNetwork {
                        MetricSection(
                            title: Strings.network(),
                            value: networkSummary,
                            values: normalizedNetworkTrend,
                            severity: .normal,
                            details: networkDetails
                        )
                    }

                    if state.visibility.showTemperature {
                        MetricSection(
                            title: Strings.temperature(),
                            value: TemperatureFormatter.displayString(for: state.latestTemperatureSample),
                            values: state.temperatureHistory.samples.map(\.trendValue),
                            severity: state.temperatureMenuBarTextStyle,
                            details: temperatureDetails
                        )
                    }

                    if !state.hasVisibleMetric {
                        EmptyMetricsState()
                    }

                    lastUpdatedFooter
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 1)
            }
            .frame(maxWidth: .infinity, maxHeight: 245)

            Divider()

            LaunchAtLoginControl(settings: launchAtLoginSettings)

            Divider()

            Button(Strings.quit(), action: quit)
                .font(.caption)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: popoverWidth, height: popoverHeight, alignment: .topLeading)
    }

    private var appInfoHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Mac Metrics View")
                    .font(.callout.weight(.semibold))

                Text(Strings.versionBeta())
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(Strings.developedBy())
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var cpuDetails: [MetricDetailRow] {
        [
            MetricDetailRow(label: Strings.cpuUser(), value: CPUFormatter.percentageString(state.latestSample?.userUsagePercent)),
            MetricDetailRow(label: Strings.cpuSystem(), value: CPUFormatter.percentageString(state.latestSample?.systemUsagePercent)),
            MetricDetailRow(label: Strings.cpuIdle(), value: CPUFormatter.percentageString(state.latestSample?.idlePercent))
        ]
    }

    private var ramDetails: [MetricDetailRow] {
        [
            MetricDetailRow(label: Strings.ramTotal(), value: RAMFormatter.usedGBString(state.latestRAMSample?.totalGB)),
            MetricDetailRow(label: Strings.ramUsed(), value: CPUFormatter.percentageString(state.latestRAMSample?.usedPercent))
        ]
    }

    private var networkDetails: [MetricDetailRow] {
        [
            MetricDetailRow(
                label: Strings.download(),
                value: NetworkFormatter.byteRateString(state.latestNetworkSample?.downloadBytesPerSecond)
            ),
            MetricDetailRow(
                label: Strings.upload(),
                value: NetworkFormatter.byteRateString(state.latestNetworkSample?.uploadBytesPerSecond)
            )
        ]
    }

    private var lastUpdatedFooter: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Strings.updated())
                .foregroundStyle(.secondary)
            Spacer()
            Text(lastUpdatedText)
                .monospacedDigit()
        }
        .font(.caption2)
        .accessibilityElement(children: .combine)
    }

    private var lastUpdatedText: String {
        guard let date = [
            state.latestSample?.timestamp,
            state.latestRAMSample?.timestamp,
            state.latestNetworkSample?.timestamp,
            state.latestTemperatureSample?.timestamp
        ].compactMap({ $0 }).max() else {
            return "--"
        }

        return Self.timeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter
    }()

    private var networkSummary: String {
        "↓ \(NetworkFormatter.byteRateString(state.latestNetworkSample?.downloadBytesPerSecond)) ↑ \(NetworkFormatter.byteRateString(state.latestNetworkSample?.uploadBytesPerSecond))"
    }

    private var normalizedNetworkTrend: [Double] {
        let rates = state.networkHistory.samples.map(\.totalBytesPerSecond)
        guard let maxRate = rates.max(), maxRate > 0 else { return rates }

        return rates.map { $0 / maxRate * 100 }
    }

    private var temperatureDetails: [MetricDetailRow] {
        [
            MetricDetailRow(label: Strings.temperatureStateRow(), value: state.latestTemperatureSample?.state.localizedName() ?? Strings.unavailable())
        ]
    }
}

private struct LaunchAtLoginControl: View {
    @ObservedObject var settings: LaunchAtLoginSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: 8) {
                Text(Strings.openAtLogin())
                    .lineLimit(1)
                    .foregroundStyle(settings.isAvailable ? .primary : .secondary)

                Spacer()

                Toggle(Strings.openAtLogin(), isOn: Binding(
                    get: { settings.isEnabled },
                    set: { settings.setEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!settings.isAvailable)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(settings.status.localizedName())
                    .foregroundStyle(.secondary)

                if settings.showsError {
                    Text(Strings.loginChangeFailed())
                        .foregroundStyle(.red)
                }
            }
            .font(.caption2)
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MetricVisibilityControls: View {
    @Binding var cpuVisible: Bool
    @Binding var ramVisible: Bool
    @Binding var networkVisible: Bool
    @Binding var temperatureVisible: Bool
    @Binding var identifierStyle: MetricDisplaySettings.IdentifierStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                GridRow {
                    SettingSwitch(title: "CPU", isOn: $cpuVisible)
                    SettingSwitch(title: "RAM", isOn: $ramVisible)
                }

                GridRow {
                    SettingSwitch(title: Strings.network(), isOn: $networkVisible)
                    SettingSwitch(title: Strings.temperature(), isOn: $temperatureVisible)
                }
            }

            HStack(spacing: 8) {
                MetricIdentifierPicker(identifierStyle: $identifierStyle)
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MetricIdentifierPicker: View {
    @Binding var identifierStyle: MetricDisplaySettings.IdentifierStyle

    var body: some View {
        HStack(spacing: 6) {
            Text(Strings.displayLabel())
                .lineLimit(1)
                .foregroundStyle(.primary)
                .frame(width: 88, alignment: .leading)

            Picker(Strings.displayLabel(), selection: $identifierStyle) {
                Text(Strings.displayIcon()).tag(MetricDisplaySettings.IdentifierStyle.icons)
                Text(Strings.displayText()).tag(MetricDisplaySettings.IdentifierStyle.labels)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 150)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingSwitch: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .lineLimit(1)
                .foregroundStyle(.primary)
                .frame(width: 88, alignment: .leading)

            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .frame(width: 158, alignment: .leading)
    }
}

private struct MetricSection: View {
    let title: String
    let value: String
    let values: [Double]
    let severity: CPUMenuBarTextStyle
    let details: [MetricDetailRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.callout.weight(.semibold))

                if let severityLabel {
                    Text(severityLabel)
                        .font(.caption2)
                        .foregroundStyle(severityColor)
                }

                Spacer()

                Text(value)
                    .font(.system(.body, design: .default, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(severityColor)
                    .accessibilityLabel("\(title), \(value)\(severityAccessibilitySuffix)")
            }

            if !values.isEmpty {
                SparklineView(values: values, height: 18)
                    .foregroundStyle(.tertiary)
            }

            MetricDetailGrid(rows: details)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)

        Divider()
    }

    private var severityLabel: String? {
        switch severity {
        case .normal:
            return nil
        case .elevatedCPU:
            return Strings.severityElevated()
        case .highCPU:
            return Strings.severityHigh()
        }
    }

    private var severityAccessibilitySuffix: String {
        guard let severityLabel else { return "" }
        return ", \(severityLabel)"
    }

    private var severityColor: Color {
        switch severity {
        case .normal:
            return .primary
        case .elevatedCPU:
            return .orange
        case .highCPU:
            return .red
        }
    }
}

private struct MetricDetailGrid: View {
    let rows: [MetricDetailRow]

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 4) {
            ForEach(rows) { row in
                GridRow {
                    Text(row.label)
                        .foregroundStyle(.secondary)
                    Text(row.value)
                        .monospacedDigit()
                }
            }
        }
        .font(.caption)
    }
}

private struct MetricDetailRow: Identifiable {
    let label: String
    let value: String

    var id: String { label }
}

private struct EmptyMetricsState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Strings.noMetricsTitle())
                .font(.callout.weight(.semibold))
            Text(Strings.noMetricsHint())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}

private extension NetworkSample {
    var totalBytesPerSecond: Double {
        downloadBytesPerSecond + uploadBytesPerSecond
    }
}
