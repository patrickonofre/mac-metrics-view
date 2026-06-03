import AppKit
import SwiftUI

struct PopoverView: View {
    @ObservedObject var state: CPUState
    @ObservedObject var launchAtLoginSettings: LaunchAtLoginSettings
    let dismissPopover: () -> Void
    let quit: () -> Void

    private let popoverWidth: CGFloat = 380

    var body: some View {
        // Content-driven height: data and config each take exactly the room their content
        // needs, top to bottom — no forced split (which left the short data pane with a
        // void and clipped the taller config pane). The popover resizes to fit; nothing
        // scrolls. Width is fixed.
        VStack(alignment: .leading, spacing: 12) {
            headerBar

            if CleaningRecoveryPresentation.showsRecoveryBanner(isAccessibilityGranted: state.isAccessibilityGranted) {
                RecoveryBanner(wasResetByUpdate: state.accessibilityResetByUpdate)
            }

            dataPane

            Divider()

            configPane
        }
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: popoverWidth, alignment: .topLeading)
        .onAppear {
            state.refreshAccessibilityAuthorization()
        }
        .onDisappear {
            // If the popover is dismissed mid-recovery, stop the probe poll loop.
            // No-op unless we were awaiting a grant.
            state.cancelAccessibilityRecovery()
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

    // MARK: - Data pane (top half)

    private var dataPane: some View {
        // Always shows every metric; the visibility toggles only affect the menu bar.
        VStack(alignment: .leading, spacing: 8) {
            MetricRow(
                symbol: "cpu",
                title: "CPU",
                value: CPUFormatter.percentageString(state.latestSample?.totalUsagePercent),
                values: state.history.samples.map(\.totalUsagePercent),
                severity: state.menuBarTextStyle
            )

            MetricRow(
                symbol: "memorychip",
                title: "RAM",
                value: RAMFormatter.valueString(for: state.latestRAMSample, metric: state.ramMenuBarMetric),
                values: ramTrend,
                severity: state.ramMenuBarTextStyle
            )

            MetricRow(
                symbol: "network",
                title: Strings.network(),
                value: networkSummary,
                values: normalizedNetworkTrend,
                severity: .normal
            )

            MetricRow(
                symbol: "thermometer",
                title: Strings.temperature(),
                value: TemperatureFormatter.displayString(for: state.latestTemperatureSample),
                values: state.temperatureHistory.samples.map(\.trendValue),
                severity: state.temperatureMenuBarTextStyle
            )

            MetricRow(
                symbol: "internaldrive",
                title: Strings.disk(),
                value: DiskFormatter.menuBarTitle(
                    for: state.latestDiskSample,
                    metric: state.diskMenuBarMetric,
                    showLabel: false
                ),
                values: normalizedDiskTrend,
                severity: state.diskMenuBarTextStyle
            )

            // Always shown (like every metric); the visibility toggle below only curates
            // the menu bar. Empty/zero state is the localized copy, never an error.
            MetricRow(
                symbol: "number",
                title: Strings.tokens(),
                value: state.tokenRowValue,
                values: state.tokenSparkline,
                severity: .normal
            )

            if !state.tokenIsEmpty {
                TokenBreakdownRow(breakdown: state.tokenBreakdown)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Config pane (bottom half)

    private var configPane: some View {
        VStack(alignment: .leading, spacing: 14) {
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

                TokenControls(state: state)

                Divider()

                LaunchAtLoginControl(settings: launchAtLoginSettings)

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

            Text(Strings.developedBy())
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Derived values

    // Sparkline follows the selected RAM value so the row stays consistent with the picker.
    private var ramTrend: [Double] {
        switch state.ramMenuBarMetric {
        case .pressure:
            return state.ramHistory.samples.map(\.pressurePercent)
        case .appMemory:
            return state.ramHistory.samples.map(\.appMemoryPercent)
        }
    }

    private var networkSummary: String {
        "↓ \(NetworkFormatter.byteRateString(state.latestNetworkSample?.downloadBytesPerSecond)) ↑ \(NetworkFormatter.byteRateString(state.latestNetworkSample?.uploadBytesPerSecond))"
    }

    private var normalizedNetworkTrend: [Double] {
        let rates = state.networkHistory.samples.map(\.totalBytesPerSecond)
        guard let maxRate = rates.max(), maxRate > 0 else { return rates }

        return rates.map { $0 / maxRate * 100 }
    }

    private var normalizedDiskTrend: [Double] {
        let rates = state.diskHistory.samples.map(\.totalBytesPerSecond)
        guard let maxRate = rates.max(), maxRate > 0 else { return rates }

        return rates.map { $0 / maxRate * 100 }
    }
}

// MARK: - Compact metric row

private struct MetricRow: View {
    let symbol: String
    let title: String
    let value: String
    let values: [Double]
    let severity: CPUMenuBarTextStyle

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .imageScale(.small)
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .center)

            Text(title)
                .font(.callout)
                .lineLimit(1)

            Spacer(minLength: 8)

            if !values.isEmpty {
                SparklineView(values: values, height: 16)
                    .foregroundStyle(.tertiary)
                    .frame(width: 56)
            }

            Text(value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(severityColor)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)\(severitySuffix)")
    }

    private var severityColor: Color {
        switch severity {
        case .normal:
            return .primary
        case .elevatedCPU:
            return Color(nsColor: .systemOrange)
        case .highCPU:
            return Color(nsColor: .systemRed)
        }
    }

    private var severitySuffix: String {
        switch severity {
        case .normal:
            return ""
        case .elevatedCPU:
            return ", \(Strings.severityElevated())"
        case .highCPU:
            return ", \(Strings.severityHigh())"
        }
    }
}

// MARK: - Token breakdown + controls

/// Input / output / cache breakdown shown under the token metric row, indented to align
/// beneath the row title.
private struct TokenBreakdownRow: View {
    let breakdown: [(label: String, value: String)]

    var body: some View {
        HStack(spacing: 12) {
            Spacer().frame(width: 26)   // icon (18) + row spacing (8)

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

/// Token meter configuration: menu-bar visibility toggle, scope picker, window picker,
/// and the Reset button. All controls bind to `CPUState` setters, mirroring the other
/// config controls.
private struct TokenControls: View {
    @ObservedObject var state: CPUState

    @State private var showHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                HStack(spacing: 3) {
                    Text(Strings.tokens())
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
                    .help(Strings.tokenSourceHelpTitle())
                }
                .frame(width: 88, alignment: .leading)

                Toggle(Strings.tokens(), isOn: Binding(
                    get: { state.visibility.showTokens },
                    set: { state.setTokenVisible($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)

                if let models = state.tokenActiveModels {
                    Text(models)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .accessibilityLabel("\(Strings.tokens()), \(models)")
                }

                Spacer(minLength: 0)
            }

            if showHelp {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Strings.tokenSourceHelpTitle())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(Strings.tokenSourceHelp())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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

            picker(
                label: Strings.tokenScopeLabel(),
                selection: Binding(get: { state.tokenScope }, set: { state.setTokenScope($0) })
            ) {
                Text(Strings.tokenScopeGlobal()).tag(TokenScope.global)
                Text(Strings.tokenScopeProject()).tag(TokenScope.project)
                Text(Strings.tokenScopeSession()).tag(TokenScope.session)
            }

            picker(
                label: Strings.tokenWindowLabel(),
                selection: Binding(get: { state.tokenMenuBarWindow }, set: { state.setTokenMenuBarWindow($0) })
            ) {
                Text(Strings.tokenWindowToday()).tag(TokenWindow.today)
                Text(Strings.tokenWindowLastHour()).tag(TokenWindow.lastHour)
                Text(Strings.tokenWindowLast24h()).tag(TokenWindow.last24h)
                Text(Strings.tokenWindowSinceReset()).tag(TokenWindow.sinceReset)
            }

            Button(Strings.tokenReset()) {
                state.resetTokenCounter()
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.accentColor)
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.18), value: showHelp)
    }

    private func picker<Value: Hashable, Content: View>(
        label: String,
        selection: Binding<Value>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .lineLimit(1)
                .foregroundStyle(.primary)
                .frame(width: 88, alignment: .leading)

            Picker(label, selection: selection, content: content)
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 150, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

            // The toggle itself shows on/off; only surface the line when something failed.
            if settings.showsError {
                Text(Strings.loginChangeFailed())
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
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

            // Always visible: these choose the value shown for RAM and Disk in both the
            // popover and the menu bar, so they apply even when the metric is hidden from
            // the menu bar.
            HStack(spacing: 8) {
                RAMMenuBarMetricPicker(ramMenuBarMetric: $ramMenuBarMetric)
            }

            HStack(spacing: 8) {
                DiskMenuBarMetricPicker(diskMenuBarMetric: $diskMenuBarMetric)
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
            Text(Strings.diskMenuBarMetric())
                .lineLimit(1)
                .foregroundStyle(.primary)
                .frame(width: 88, alignment: .leading)

            Picker(Strings.diskMenuBarMetric(), selection: $diskMenuBarMetric) {
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
                    Text(Strings.ramMenuBarMetric())
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

                Picker(Strings.ramMenuBarMetric(), selection: $ramMenuBarMetric) {
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

            switch CleaningRecoveryPresentation.cardState(
                isAccessibilityGranted: isAccessibilityGranted,
                recoveryPhase: state.recoveryPhase
            ) {
            case .granted:
                grantedControls
            case .applying:
                applyingIndicator
            case .awaitingGuidance:
                recoveryGuidance
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Preserved unchanged: duration picker + Iniciar.
    private var grantedControls: some View {
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
    }

    // Transient: the detected grant is being applied via relaunch.
    private var applyingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(Strings.cleaningApplyingPermission())
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // Self-healing recovery: open Settings + begin probing; the app detects the
    // re-added grant and relaunches on its own (no manual "reload" button).
    private var recoveryGuidance: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "lock.trianglebadge.exclamationmark")
                    .foregroundStyle(.orange)
                Text(Strings.cleaningPermissionRequired())
                    .foregroundStyle(.secondary)
                Spacer()
                Button(Strings.cleaningOpenAccessibility()) {
                    state.beginAccessibilityRecovery()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.accentColor)
            }

            Text(CleaningRecoveryPresentation.guidance(wasResetByUpdate: wasResetByUpdate)())
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if state.recoveryPhase == .awaitingGrant {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(Strings.cleaningRecoveryChecking())
                        .foregroundStyle(.secondary)
                }
                .font(.caption2)
            }
        }
        .font(.caption)
    }
}

// MARK: - Recovery header banner

private struct RecoveryBanner: View {
    let wasResetByUpdate: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .imageScale(.medium)

            VStack(alignment: .leading, spacing: 1) {
                Text(CleaningRecoveryPresentation.bannerTitle(wasResetByUpdate: wasResetByUpdate)())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(CleaningRecoveryPresentation.bannerMessage(wasResetByUpdate: wasResetByUpdate)())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.35))
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Network helper

private extension NetworkSample {
    var totalBytesPerSecond: Double {
        downloadBytesPerSecond + uploadBytesPerSecond
    }
}
