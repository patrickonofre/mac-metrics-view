import SwiftUI

/// Settings tab body: everything the user *sets* — per-metric menu-bar visibility,
/// identifier style, RAM/Disk metric variants, and
/// launch-at-login. Controls are relocated verbatim from `PopoverView.swift`
/// (task_05); no cleaning/update actions live here (those are in `ActionsTab`).
struct SettingsTab: View {
    @ObservedObject var state: CPUState
    /// Observed separately from `state` (task-005): the controls below are the data
    /// `metrics` owns, so this tab reads/writes it at the point of use.
    @ObservedObject var metrics: SystemMetricsModel
    @ObservedObject var launchAtLoginSettings: LaunchAtLoginSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            MetricVisibilityControls(
                cpuVisible: Binding(
                    get: { metrics.visibility.showCPU },
                    set: { metrics.setCPUVisible($0) }
                ),
                ramVisible: Binding(
                    get: { metrics.visibility.showRAM },
                    set: { metrics.setRAMVisible($0) }
                ),
                networkVisible: Binding(
                    get: { metrics.visibility.showNetwork },
                    set: { metrics.setNetworkVisible($0) }
                ),
                temperatureVisible: Binding(
                    get: { metrics.visibility.showTemperature },
                    set: { metrics.setTemperatureVisible($0) }
                ),
                diskVisible: Binding(
                    get: { metrics.visibility.showDisk },
                    set: { metrics.setDiskVisible($0) }
                ),
                batteryVisible: Binding(
                    get: { metrics.visibility.showBattery },
                    set: { metrics.setBatteryVisible($0) }
                ),
                identifierStyle: Binding(
                    get: { metrics.display.identifierStyle },
                    set: { metrics.setMetricIdentifierStyle($0) }
                ),
                ramMenuBarMetric: Binding(
                    get: { metrics.display.ramMenuBarMetric },
                    set: { metrics.setRAMMenuBarMetric($0) }
                ),
                diskMenuBarMetric: Binding(
                    get: { metrics.display.diskMenuBarMetric },
                    set: { metrics.setDiskMenuBarMetric($0) }
                ),
                updateRate: Binding(
                    get: { metrics.updateRate },
                    set: { metrics.setUpdateRate($0) }
                )
            )

            Divider()

            AmbientThemeControls(state: state)

            Divider()

            LaunchAtLoginControl(settings: launchAtLoginSettings)
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Ambient theme suggestion controls

/// Settings for the ambient-light theme suggestion: opt-in toggle, the live light
/// readout (FR-10, doubles as a calibration aid), and the dark/light thresholds +
/// dwell. All bind through `CPUState.setAmbientThemeSettings`, which persists, rebuilds
/// the engine, and re-evaluates. Threshold setters clamp so `highLux > lowLux` always
/// holds (otherwise the struct would reset the whole band to defaults).
struct AmbientThemeControls: View {
    @ObservedObject var state: CPUState

    @State private var showHelp = false

    private var settings: AmbientThemeSettings { state.ambientThemeSettings }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                HStack(spacing: 3) {
                    Text(Strings.ambientThemeSectionTitle())
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    Button { showHelp.toggle() } label: {
                        Image(systemName: showHelp ? "info.circle.fill" : "info.circle")
                            .foregroundStyle(showHelp ? Color.accentColor : .secondary)
                            .imageScale(.small)
                    }
                    .buttonStyle(.plain)
                    .help(Strings.ambientThemeSectionTitle())
                }

                Spacer()

                Toggle(Strings.ambientThemeEnable(), isOn: Binding(
                    get: { settings.isEnabled },
                    set: { newValue in
                        var copy = settings
                        copy.isEnabled = newValue
                        state.setAmbientThemeSettings(copy)
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }

            if showHelp {
                Text(Strings.ambientThemeHelp())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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

            if settings.isEnabled {
                // Live light readout (FR-10) — also the calibration reference for the
                // thresholds below. Falls back to "no sensor" on hardware without an ALS.
                HStack(spacing: 6) {
                    Text(Strings.ambientCurrentLight())
                        .foregroundStyle(.primary)
                        .frame(width: 120, alignment: .leading)
                    if let lux = state.latestAmbientSample?.lux {
                        Text("\(Int(lux))")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    } else {
                        Text(Strings.ambientNoSensor())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                stepperRow(
                    label: Strings.ambientThresholdDark(),
                    value: Int(settings.lowLux),
                    binding: Binding(
                        get: { settings.lowLux },
                        // Keep a non-empty dead band: dark threshold stays below the light one.
                        set: { newValue in
                            var copy = settings
                            copy.lowLux = min(newValue, copy.highLux - 1)
                            state.setAmbientThemeSettings(copy)
                        }
                    )
                )

                stepperRow(
                    label: Strings.ambientThresholdLight(),
                    value: Int(settings.highLux),
                    binding: Binding(
                        get: { settings.highLux },
                        set: { newValue in
                            var copy = settings
                            copy.highLux = max(newValue, copy.lowLux + 1)
                            state.setAmbientThemeSettings(copy)
                        }
                    )
                )

                stepperRow(
                    label: Strings.ambientDwellLabel(),
                    value: Int(settings.dwellSeconds),
                    binding: Binding(
                        get: { settings.dwellSeconds },
                        set: { newValue in
                            var copy = settings
                            copy.dwellSeconds = max(0, newValue)
                            state.setAmbientThemeSettings(copy)
                        }
                    ),
                    range: 0...120
                )
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.18), value: showHelp)
    }

    private func stepperRow(
        label: String,
        value: Int,
        binding: Binding<Double>,
        range: ClosedRange<Double> = 0...2000
    ) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .lineLimit(1)
                .foregroundStyle(.primary)
                .frame(width: 150, alignment: .leading)
            Stepper(value: binding, in: range, step: 5) {
                Text("\(value)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Launch at login

/// Relocated from `PopoverView.swift` (task_05).
struct LaunchAtLoginControl: View {
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

// MARK: - Visibility + display controls

/// Relocated from `PopoverView.swift` (task_05).
struct MetricVisibilityControls: View {
    @Binding var cpuVisible: Bool
    @Binding var ramVisible: Bool
    @Binding var networkVisible: Bool
    @Binding var temperatureVisible: Bool
    @Binding var diskVisible: Bool
    @Binding var batteryVisible: Bool
    @Binding var identifierStyle: MetricDisplaySettings.IdentifierStyle
    @Binding var ramMenuBarMetric: MetricDisplaySettings.RAMMenuBarMetric
    @Binding var diskMenuBarMetric: MetricDisplaySettings.DiskMenuBarMetric
    @Binding var updateRate: Int

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
                    SettingSwitch(title: Strings.battery(), isOn: $batteryVisible)
                }
            }

            HStack(spacing: 8) {
                MetricIdentifierPicker(identifierStyle: $identifierStyle)
            }

            HStack(spacing: 8) {
                UpdateRatePicker(updateRate: $updateRate)
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

struct UpdateRatePicker: View {
    @Binding var updateRate: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(Strings.updateRateLabel())
                .lineLimit(1)
                .foregroundStyle(.primary)
                .frame(width: 88, alignment: .leading)

            Picker(Strings.updateRateLabel(), selection: $updateRate) {
                Text(Strings.updateRateSeconds1()).tag(1)
                Text(Strings.updateRateSeconds2()).tag(2)
                Text(Strings.updateRateSeconds3()).tag(3)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 150)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Relocated from `PopoverView.swift` (task_05).
struct DiskMenuBarMetricPicker: View {
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

/// Relocated from `PopoverView.swift` (task_05).
struct RAMMenuBarMetricPicker: View {
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

                // A `.menu` dropdown (not segmented) so three full-length labels fit at the
                // fixed 150pt control width without truncation (ADR-002).
                Picker(Strings.ramMenuBarMetric(), selection: $ramMenuBarMetric) {
                    ForEach(MetricDisplaySettings.RAMMenuBarMetric.menuBarPickerOrder, id: \.self) { mode in
                        Text(mode.menuBarPickerLabel()).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 150)
            }

            if showHelp {
                VStack(alignment: .leading, spacing: 7) {
                    helpRow(term: Strings.ramUsedTotal(), detail: Strings.ramUsedTotalHelp())
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

/// Relocated from `PopoverView.swift` (task_05).
struct MetricIdentifierPicker: View {
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

/// Relocated from `PopoverView.swift` (task_05).
struct SettingSwitch: View {
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
