import SwiftUI

/// Settings tab body: everything the user *sets* — per-metric menu-bar visibility,
/// identifier style, disk metric variants, and
/// launch-at-login. Controls are relocated verbatim from `PopoverView.swift`
/// (task_05); no cleaning/update actions live here (those are in `ActionsTab`).
struct SettingsTab: View {
    /// The model owns and persists preferences. Keep view snapshots of just those
    /// publishers so live samples do not invalidate Settings.
    let metrics: SystemMetricsModel
    @ObservedObject var launchAtLoginSettings: LaunchAtLoginSettings
    @State private var visibility: MetricVisibilitySettings
    @State private var display: MetricDisplaySettings

    @MainActor
    init(metrics: SystemMetricsModel, launchAtLoginSettings: LaunchAtLoginSettings) {
        self.metrics = metrics
        self.launchAtLoginSettings = launchAtLoginSettings
        _visibility = State(initialValue: metrics.visibility)
        _display = State(initialValue: metrics.display)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MetricVisibilityControls(
                cpuVisible: Binding(
                    get: { visibility.showCPU },
                    set: { metrics.setCPUVisible($0) }
                ),
                ramVisible: Binding(
                    get: { visibility.showRAM },
                    set: { metrics.setRAMVisible($0) }
                ),
                networkVisible: Binding(
                    get: { visibility.showNetwork },
                    set: { metrics.setNetworkVisible($0) }
                ),
                temperatureVisible: Binding(
                    get: { visibility.showTemperature },
                    set: { metrics.setTemperatureVisible($0) }
                ),
                diskVisible: Binding(
                    get: { visibility.showDisk },
                    set: { metrics.setDiskVisible($0) }
                ),
                batteryVisible: Binding(
                    get: { visibility.showBattery },
                    set: { metrics.setBatteryVisible($0) }
                ),
                identifierStyle: Binding(
                    get: { display.identifierStyle },
                    set: { metrics.setMetricIdentifierStyle($0) }
                ),
                diskMenuBarMetric: Binding(
                    get: { display.diskMenuBarMetric },
                    set: { metrics.setDiskMenuBarMetric($0) }
                ),
                updateRate: Binding(
                    get: { display.updateRate },
                    set: { metrics.setUpdateRate($0) }
                )
            )

            Divider()

            LaunchAtLoginControl(settings: launchAtLoginSettings)
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onReceive(metrics.$visibility) { newValue in
            if visibility != newValue { visibility = newValue }
        }
        .onReceive(metrics.$display) { newValue in
            if display != newValue { display = newValue }
        }
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
    @Binding var diskMenuBarMetric: MetricDisplaySettings.DiskMenuBarMetric
    @Binding var updateRate: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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

            Divider()

            MetricIdentifierPicker(identifierStyle: $identifierStyle)
            UpdateRatePicker(updateRate: $updateRate)
            DiskMenuBarMetricPicker(diskMenuBarMetric: $diskMenuBarMetric)
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
