import AppKit
import SwiftUI

struct PopoverView: View {
    @ObservedObject var state: CPUState
    @ObservedObject var launchAtLoginSettings: LaunchAtLoginSettings
    let dismissPopover: () -> Void
    let quit: () -> Void

    private let popoverWidth: CGFloat = 380
    private let popoverHeight: CGFloat = 520

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
                diskVisible: Binding(
                    get: { state.visibility.showDisk },
                    set: { state.setDiskVisible($0) }
                ),
                identifierStyle: Binding(
                    get: { state.display.identifierStyle },
                    set: { state.setMetricIdentifierStyle($0) }
                ),
                ramMenuBarMetric: Binding(
                    get: { state.display.ramMenuBarMetric },
                    set: { state.setRAMMenuBarMetric($0) }
                ),
                diskMenuBarMetric: Binding(
                    get: { state.display.diskMenuBarMetric },
                    set: { state.setDiskMenuBarMetric($0) }
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
                            value: RAMFormatter.usedGBString(state.latestRAMSample?.appMemoryGB),
                            values: state.ramHistory.samples.map(\.appMemoryPercent),
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

                    if state.visibility.showDisk {
                        MetricSection(
                            title: Strings.disk(),
                            value: DiskFormatter.menuBarTitle(
                                for: state.latestDiskSample,
                                metric: state.diskMenuBarMetric,
                                showLabel: false
                            ),
                            values: normalizedDiskTrend,
                            severity: state.diskMenuBarTextStyle,
                            details: diskDetails
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

            UpdatesControl(state: state)

            Divider()

            CleaningLockSection(
                state: state,
                isAccessibilityGranted: state.isAccessibilityGranted,
                wasResetByUpdate: state.accessibilityResetByUpdate,
                onStart: {
                    state.startCleaningLock()
                    dismissPopover()
                }
            )

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
        .onAppear {
            state.refreshAccessibilityAuthorization()
        }
    }

    private var appInfoHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Mac Metrics View")
                    .font(.callout.weight(.semibold))

                Text(Strings.appVersion())
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
        let sample = state.latestRAMSample
        let appMemory = "\(RAMFormatter.usedGBString(sample?.appMemoryGB)) (\(CPUFormatter.percentageString(sample?.appMemoryPercent)))"
        return [
            MetricDetailRow(label: Strings.ramAppMemory(), value: appMemory),
            MetricDetailRow(label: Strings.ramPressure(), value: CPUFormatter.percentageString(sample?.pressurePercent)),
            MetricDetailRow(label: Strings.ramTotal(), value: RAMFormatter.usedGBString(sample?.totalGB))
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
            state.latestTemperatureSample?.timestamp,
            state.latestDiskSample?.timestamp
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

    private var normalizedDiskTrend: [Double] {
        let rates = state.diskHistory.samples.map(\.totalBytesPerSecond)
        guard let maxRate = rates.max(), maxRate > 0 else { return rates }

        return rates.map { $0 / maxRate * 100 }
    }

    private var diskDetails: [MetricDetailRow] {
        let totals = DiskWindowStats.recentTotalBytes(in: state.diskHistory, interval: state.diskSampleInterval)
        let peaks = DiskWindowStats.recentPeakRates(in: state.diskHistory)

        return [
            MetricDetailRow(label: Strings.diskRead(), value: DiskFormatter.combinedRateString(state.latestDiskSample?.readBytesPerSecond)),
            MetricDetailRow(label: Strings.diskWrite(), value: DiskFormatter.combinedRateString(state.latestDiskSample?.writeBytesPerSecond)),
            MetricDetailRow(label: Strings.diskRecentTotalRead(), value: DiskFormatter.byteCountString(totals.read)),
            MetricDetailRow(label: Strings.diskRecentTotalWrite(), value: DiskFormatter.byteCountString(totals.written)),
            MetricDetailRow(label: Strings.diskRecentPeakRead(), value: DiskFormatter.combinedRateString(peaks.read)),
            MetricDetailRow(label: Strings.diskRecentPeakWrite(), value: DiskFormatter.combinedRateString(peaks.write))
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

private struct UpdatesControl: View {
    @ObservedObject var state: CPUState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(Strings.autoUpdateCheck()) {
                state.checkForUpdates()
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.accentColor)

            if let version = state.availableUpdateVersion {
                Text(Strings.autoUpdateAvailable(version))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
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
    @Binding var diskVisible: Bool
    @Binding var identifierStyle: MetricDisplaySettings.IdentifierStyle
    @Binding var ramMenuBarMetric: MetricDisplaySettings.RAMMenuBarMetric
    @Binding var diskMenuBarMetric: MetricDisplaySettings.DiskMenuBarMetric

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

                GridRow {
                    SettingSwitch(title: Strings.disk(), isOn: $diskVisible)
                }
            }

            HStack(spacing: 8) {
                MetricIdentifierPicker(identifierStyle: $identifierStyle)
            }

            if ramVisible {
                HStack(spacing: 8) {
                    RAMMenuBarMetricPicker(ramMenuBarMetric: $ramMenuBarMetric)
                }
            }

            if diskVisible {
                HStack(spacing: 8) {
                    DiskMenuBarMetricPicker(diskMenuBarMetric: $diskMenuBarMetric)
                }
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DiskMenuBarMetricPicker: View {
    @Binding var diskMenuBarMetric: MetricDisplaySettings.DiskMenuBarMetric

    var body: some View {
        HStack(spacing: 6) {
            Text("\(Strings.disk()) \(Strings.diskMenuBarMetric())")
                .lineLimit(1)
                .foregroundStyle(.primary)
                .frame(width: 88, alignment: .leading)

            Picker("\(Strings.disk()) \(Strings.diskMenuBarMetric())", selection: $diskMenuBarMetric) {
                Text(Strings.diskMetricCombinedShort()).tag(MetricDisplaySettings.DiskMenuBarMetric.combined)
                Text(Strings.diskMetricSplitShort()).tag(MetricDisplaySettings.DiskMenuBarMetric.split)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 150)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RAMMenuBarMetricPicker: View {
    @Binding var ramMenuBarMetric: MetricDisplaySettings.RAMMenuBarMetric

    @State private var showHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                HStack(spacing: 3) {
                    Text("RAM \(Strings.ramMenuBarMetric())")
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    Button {
                        showHelp.toggle()
                    } label: {
                        Image(systemName: showHelp ? "info.circle.fill" : "info.circle")
                            .foregroundStyle(showHelp ? Color.accentColor : .secondary)
                            .imageScale(.small)
                    }
                    .buttonStyle(.plain)
                    .help(Strings.ramMenuBarMetricHelpTitle())
                }
                .frame(width: 88, alignment: .leading)

                Picker("RAM \(Strings.ramMenuBarMetric())", selection: $ramMenuBarMetric) {
                    Text(Strings.ramMetricAppMemoryShort()).tag(MetricDisplaySettings.RAMMenuBarMetric.appMemory)
                    Text(Strings.ramMetricPressureShort()).tag(MetricDisplaySettings.RAMMenuBarMetric.pressure)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 150)
            }

            if showHelp {
                VStack(alignment: .leading, spacing: 7) {
                    helpRow(term: Strings.ramAppMemory(), detail: Strings.ramAppMemoryHelp())
                    helpRow(term: Strings.ramPressure(), detail: Strings.ramPressureHelp())
                }
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08))
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.18), value: showHelp)
    }

    private func helpRow(term: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(term)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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

// MARK: - Cleaning lock section

private struct CleaningLockSection: View {
    @ObservedObject var state: CPUState
    let isAccessibilityGranted: Bool
    let wasResetByUpdate: Bool
    let onStart: () -> Void

    private static let presetLabels: [(TimeInterval, String)] = [
        (15,  "15s"),
        (30,  "30s"),
        (60,  "1min"),
        (120, "2min"),
        (300, "5min")
    ]

    private var durationBinding: Binding<TimeInterval> {
        Binding<TimeInterval>(
            get: { state.cleaningLockSettings.selectedDuration },
            set: { state.selectLockDuration($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Modo limpeza")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)

            if isAccessibilityGranted {
                HStack(spacing: 8) {
                    Picker("Duração", selection: durationBinding) {
                        ForEach(Self.presetLabels, id: \.0) { duration, label in
                            Text(label).tag(duration)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: .infinity)

                    Button("Iniciar") {
                        onStart()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(state.lockPhase == .locked)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.trianglebadge.exclamationmark")
                            .foregroundStyle(.orange)
                        Text("Permissão de Acessibilidade necessária")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Conceder acesso") {
                            state.requestAccessibilityAccess()
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Color.accentColor)
                    }

                    if wasResetByUpdate {
                        Text("A atualização redefiniu a permissão. Em Acessibilidade, remova (−) o Mac Metrics View e adicione novamente — apenas ligar a entrada antiga não funciona. Depois, toque em Relançar abaixo.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Conceda o acesso em Acessibilidade e toque em Relançar abaixo. Se o Mac Metrics View já aparece na lista mas continua bloqueado, remova (−) a entrada e adicione novamente — uma entrada de uma versão anterior não vale.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 6) {
                        Text("Já concedeu?")
                            .foregroundStyle(.secondary)
                        Button("Relançar app") {
                            state.relaunchToApplyGrant()
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Color.accentColor)
                        Spacer()
                    }
                    .font(.caption2)
                }
                .font(.caption)
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Network helper

private extension NetworkSample {
    var totalBytesPerSecond: Double {
        downloadBytesPerSecond + uploadBytesPerSecond
    }
}
