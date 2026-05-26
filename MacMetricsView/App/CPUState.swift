import Foundation
import Combine

@MainActor
final class CPUState: ObservableObject {
    @Published private(set) var visibility: MetricVisibilitySettings
    @Published private(set) var display: MetricDisplaySettings
    @Published private(set) var latestSample: CPUSample?
    @Published private(set) var latestRAMSample: RAMSample?
    @Published private(set) var latestNetworkSample: NetworkSample?
    @Published private(set) var latestTemperatureSample: TemperatureSample?
    @Published private(set) var history = CPUHistory()
    @Published private(set) var ramHistory = RAMHistory()
    @Published private(set) var networkHistory = NetworkHistory()
    @Published private(set) var temperatureHistory = TemperatureHistory()

    // Cleaning-lock state — updated by AppDelegate via updateLockState(phase:remaining:)
    @Published private(set) var lockPhase: LockPhase = .idle
    @Published private(set) var lockRemaining: TimeInterval = 0
    @Published private(set) var cleaningLockSettings: CleaningLockSettings

    /// Live Accessibility (AX) permission gate for the cleaning lock.
    /// Refreshed on each popover show so a grant made in System Settings is
    /// reflected without relaunching the app.
    @Published private(set) var isAccessibilityGranted: Bool = false

    var onVisibilityChange: ((MetricVisibilitySettings.Metric, Bool) -> Void)?
    var onDisplayChange: (() -> Void)?
    /// Called by the UI when the user taps Iniciar; AppDelegate wires the actual lock start.
    var onStartLock: ((TimeInterval) -> Void)?

    private let userDefaults: UserDefaults
    private let accessibilityAuthorization: AccessibilityAuthorizationProtocol

    init(
        userDefaults: UserDefaults = .standard,
        accessibilityAuthorization: AccessibilityAuthorizationProtocol = SystemAccessibilityAuthorization()
    ) {
        self.userDefaults = userDefaults
        self.accessibilityAuthorization = accessibilityAuthorization
        visibility = MetricVisibilitySettings.load(from: userDefaults)
        display = MetricDisplaySettings.load(from: userDefaults)
        cleaningLockSettings = CleaningLockSettings.load(from: userDefaults)
        isAccessibilityGranted = accessibilityAuthorization.isTrusted
    }

    var menuBarTitle: String {
        let segments = visibleMenuBarTitles
        guard !segments.isEmpty else { return Strings.metricsPlaceholder() }
        return segments.joined(separator: "  ")
    }

    var visibleMenuBarTitles: [String] {
        var titles: [String] = []
        let showLabel = display.identifierStyle == .labels

        if visibility.showCPU {
            titles.append(CPUFormatter.menuBarTitle(for: latestSample, showLabel: showLabel))
        }

        if visibility.showRAM {
            titles.append(RAMFormatter.menuBarTitle(for: latestRAMSample, showLabel: showLabel))
        }

        if visibility.showNetwork {
            titles.append(NetworkFormatter.stableMenuBarTitle(for: latestNetworkSample, showLabel: showLabel))
        }

        if visibility.showTemperature {
            titles.append(TemperatureFormatter.menuBarTitle(for: latestTemperatureSample, showLabel: showLabel))
        }

        return titles
    }

    var menuBarTextStyle: CPUMenuBarTextStyle {
        CPUFormatter.menuBarTextStyle(for: latestSample)
    }

    var ramMenuBarTextStyle: CPUMenuBarTextStyle {
        RAMFormatter.menuBarTextStyle(for: latestRAMSample)
    }

    var temperatureMenuBarTextStyle: CPUMenuBarTextStyle {
        TemperatureFormatter.menuBarTextStyle(for: latestTemperatureSample)
    }

    var hasVisibleMetric: Bool {
        visibility.hasVisibleMetric
    }

    var accessibilityMenuBarTitle: String {
        var segments: [String] = []

        if visibility.showCPU {
            segments.append("CPU \(CPUFormatter.percentageString(latestSample?.totalUsagePercent))")
        }

        if visibility.showRAM {
            segments.append("RAM \(RAMFormatter.usedGBString(latestRAMSample?.usedGB))")
        }

        if visibility.showNetwork {
            segments.append(NetworkFormatter.stableMenuBarTitle(for: latestNetworkSample, showLabel: true))
        }

        if visibility.showTemperature {
            segments.append("\(Strings.temperature()) \(TemperatureFormatter.displayString(for: latestTemperatureSample))")
        }

        guard !segments.isEmpty else { return Strings.metricsPlaceholder() }
        return segments.joined(separator: ", ")
    }

    func update(with sample: CPUSample) {
        guard visibility.showCPU else { return }
        latestSample = sample
        history.append(sample)
    }

    func update(with sample: RAMSample) {
        guard visibility.showRAM else { return }
        latestRAMSample = sample
        ramHistory.append(sample)
    }

    func update(with sample: NetworkSample) {
        guard visibility.showNetwork else { return }
        latestNetworkSample = sample
        networkHistory.append(sample)
    }

    func update(with sample: TemperatureSample) {
        guard visibility.showTemperature else { return }
        latestTemperatureSample = sample
        temperatureHistory.append(sample)
    }

    func setCPUVisible(_ isVisible: Bool) {
        updateVisibility(metric: .cpu, isVisible: isVisible)
    }

    func setRAMVisible(_ isVisible: Bool) {
        updateVisibility(metric: .ram, isVisible: isVisible)
    }

    func setNetworkVisible(_ isVisible: Bool) {
        updateVisibility(metric: .network, isVisible: isVisible)
    }

    func setTemperatureVisible(_ isVisible: Bool) {
        updateVisibility(metric: .temperature, isVisible: isVisible)
    }

    func setMetricIdentifierStyle(_ identifierStyle: MetricDisplaySettings.IdentifierStyle) {
        guard display.identifierStyle != identifierStyle else { return }

        display.identifierStyle = identifierStyle
        display.save(to: userDefaults)
        onDisplayChange?()
    }

    private func updateVisibility(metric: MetricVisibilitySettings.Metric, isVisible: Bool) {
        guard currentVisibility(for: metric) != isVisible else { return }

        switch metric {
        case .cpu:
            visibility.showCPU = isVisible
            if isVisible {
                latestSample = nil
                history = CPUHistory()
            }
        case .ram:
            visibility.showRAM = isVisible
            if isVisible {
                latestRAMSample = nil
                ramHistory = RAMHistory()
            }
        case .network:
            visibility.showNetwork = isVisible
            if isVisible {
                latestNetworkSample = nil
                networkHistory = NetworkHistory()
            }
        case .temperature:
            visibility.showTemperature = isVisible
            if isVisible {
                latestTemperatureSample = nil
                temperatureHistory = TemperatureHistory()
            }
        }

        visibility.save(to: userDefaults)
        onVisibilityChange?(metric, isVisible)
    }

    // MARK: - Cleaning lock

    /// Persists the selected duration and updates the in-memory setting.
    func selectLockDuration(_ duration: TimeInterval) {
        guard CleaningLockSettings.presets.contains(duration) else { return }
        cleaningLockSettings.selectedDuration = duration
        cleaningLockSettings.save(to: userDefaults)
    }

    /// Fires `onStartLock` with the currently selected duration.
    /// AppDelegate owns the lock service and responds to this callback.
    func startCleaningLock() {
        onStartLock?(cleaningLockSettings.selectedDuration)
    }

    /// Re-reads the live Accessibility permission and republishes it so the
    /// cleaning-lock UI reflects a grant made in System Settings without an
    /// app relaunch. Called whenever the popover is shown.
    func refreshAccessibilityAuthorization() {
        isAccessibilityGranted = accessibilityAuthorization.isTrusted
    }

    /// Called by AppDelegate each tick and on session end to keep the UI in sync.
    func updateLockState(phase: LockPhase, remaining: TimeInterval) {
        lockPhase = phase
        lockRemaining = remaining
    }

    // MARK: - Private

    private func currentVisibility(for metric: MetricVisibilitySettings.Metric) -> Bool {
        switch metric {
        case .cpu:
            return visibility.showCPU
        case .ram:
            return visibility.showRAM
        case .network:
            return visibility.showNetwork
        case .temperature:
            return visibility.showTemperature
        }
    }
}
