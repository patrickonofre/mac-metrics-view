import SwiftUI

/// Settings tab body: everything the user *sets* — per-metric menu-bar visibility,
/// identifier style, RAM/Disk metric variants, token-source configuration, and
/// launch-at-login. Controls are relocated verbatim from `PopoverView.swift`
/// (task_05); no cleaning/update actions live here (those are in `ActionsTab`).
struct SettingsTab: View {
    @ObservedObject var state: CPUState
    @ObservedObject var launchAtLoginSettings: LaunchAtLoginSettings

    var body: some View {
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
                batteryVisible: Binding(
                    get: { state.visibility.showBattery },
                    set: { state.setBatteryVisible($0) }
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
                ),
                updateRate: Binding(
                    get: { state.updateRate },
                    set: { state.setUpdateRate($0) }
                )
            )

            Divider()

            TokenControls(state: state)

            Divider()

            LaunchAtLoginControl(settings: launchAtLoginSettings)
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Token configuration controls

/// Token meter configuration: menu-bar visibility toggle, scope picker, window
/// picker, and the Reset button. All controls bind to `CPUState` setters.
/// Relocated from `PopoverView.swift` (task_05).
struct TokenControls: View {
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
                label: Strings.tokenProviderLabel(),
                selection: Binding(get: { state.tokenProvider }, set: { state.setTokenProvider($0) })
            ) {
                Text(Strings.tokenProviderClaude()).tag(TokenProviderSelection.claude)
                Text(Strings.tokenProviderCodex()).tag(TokenProviderSelection.codex)
                Text(Strings.tokenProviderGemini()).tag(TokenProviderSelection.gemini)
                Text(Strings.tokenProviderCombined()).tag(TokenProviderSelection.combined)
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
