import Foundation
import Combine

@MainActor
final class CPUState: ObservableObject {
    /// The System metrics pillar (TD-012): CPU/RAM/network/disk/temperature/battery/GPU
    /// samples, history, and visibility/display settings. Extracted to `SystemMetricsModel`
    /// (task-005) — `StatusItemController` reads it imperatively (no
    /// observation needed; `AppDelegate`'s sampler delegates push `setNeedsTitleUpdate()`).
    /// SwiftUI consumers (`MetricsTab`, `SettingsTab`) observe `metrics` directly.
    let metrics: SystemMetricsModel

    /// The Utilities pillar (TD-012): cleaning-mode input lock + the Accessibility
    /// recovery flow that gates it. Extracted to `CleaningLockModel` (task-004), which
    /// composes `AccessibilityRecoveryModel` and bridges its changes internally. UI
    /// observes `lock` directly at the point of use (`ActionsTab`, `LockOverlayView`,
    /// `PopoverView`'s recovery banner) without bridging changes to this coordinator.
    let lock: CleaningLockModel

    /// The Utilities pillar (TD-012): the keep-awake toggle (feature `keep-awake-toggle`,
    /// persisted per `keep-awake-persistence`). Holds a `PreventUserIdleDisplaySleep`
    /// power assertion while active, and restores the last selection on launch. Like the
    /// other pillar models, not bridged to this coordinator's `objectWillChange` —
    /// `ActionsTab` observes `keepAwake` directly.
    let keepAwake: KeepAwakeModel

    /// Newest version announced by the appcast when it is more recent than the
    /// installed build, or `nil` when the app is up to date. Fed by a passive
    /// Sparkle probe (no dialog) via `setAvailableUpdateVersion(_:)`.
    @Published private(set) var availableUpdateVersion: String?

    /// Tracks if the popover is currently open. Used to lazy-load PopoverView content
    /// and completely bypass SwiftUI view graph updates when the popover is closed.
    @Published var isPopoverOpen: Bool = false {
        didSet {
            if oldValue != isPopoverOpen {
                onPopoverOpenChange?(isPopoverOpen)
            }
        }
    }


    @Published var selectedPopoverTab: PopoverTab = .metrics {
        didSet {
            guard isPopoverOpen, oldValue != selectedPopoverTab,
                  oldValue == .metrics || selectedPopoverTab == .metrics else { return }
            onMetricsTabChange?()
        }
    }

    var isMetricsTabVisible: Bool { isPopoverOpen && selectedPopoverTab == .metrics }

    var onPopoverOpenChange: ((Bool) -> Void)?
    var onMetricsTabChange: (() -> Void)?
    /// Called when the user requests a manual update check; AppDelegate forwards to the updater.
    var onCheckForUpdates: (() -> Void)?
    /// `AppDelegate` wires these against `CPUState` directly; forwarded to `lock`/
    /// `lock.recovery` so the wiring call sites need no change.
    var onStartLock: ((TimeInterval) -> Void)? {
        get { lock.onStartLock }
        set { lock.onStartLock = newValue }
    }
    var onRelaunch: (() -> Void)? {
        get { lock.recovery.onRelaunch }
        set { lock.recovery.onRelaunch = newValue }
    }
    var onRequestOpenPopover: (() -> Void)? {
        get { lock.recovery.onRequestOpenPopover }
        set { lock.recovery.onRequestOpenPopover = newValue }
    }
    /// `AppDelegate` wires these against `CPUState` directly; forwarded to `metrics` so
    /// the wiring call sites need no change.
    var onVisibilityChange: ((MetricVisibilitySettings.Metric, Bool) -> Void)? {
        get { metrics.onVisibilityChange }
        set { metrics.onVisibilityChange = newValue }
    }
    var onDisplayChange: (() -> Void)? {
        get { metrics.onDisplayChange }
        set { metrics.onDisplayChange = newValue }
    }

    private let userDefaults: UserDefaults

    init(
        userDefaults: UserDefaults = .standard,
        accessibilityAuthorization: AccessibilityAuthorizationProtocol = SystemAccessibilityAuthorization(),
        accessibilityProbe: AccessibilityProbing? = nil,
        batteryReader: BatteryReading = IOKitBatteryReader(),
        processReader: ProcessReading = LibprocProcessReader(),
        samplingExecutor: SamplingExecutor = BackgroundSamplingExecutor(),
        sleepAssertionService: SleepAssertionControlling = IOPMSleepAssertionService(),
        lidCloseService: LidCloseSleepControlling? = nil,
        powerSourceMonitor: PowerSourceMonitoring? = nil,
        currentAppVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    ) {
        self.userDefaults = userDefaults
        metrics = SystemMetricsModel(
            userDefaults: userDefaults,
            processReader: processReader,
            samplingExecutor: samplingExecutor,
            batteryReader: batteryReader
        )
        // `SystemAccessibilityProbe` is `@MainActor`, so it cannot be a default
        // argument (those are evaluated in a nonisolated context); build it here in
        // the main-actor init instead. Tests inject a `FakeAccessibilityProbe`.
        lock = CleaningLockModel(
            userDefaults: userDefaults,
            accessibilityAuthorization: accessibilityAuthorization,
            accessibilityProbe: accessibilityProbe ?? SystemAccessibilityProbe(),
            currentAppVersion: currentAppVersion
        )
        // `lidCloseService`/`powerSourceMonitor` are injectable for wiring tests
        // (feature `lid-close-keep-awake`); `nil` lets KeepAwakeModel build the real
        // SMAppService/IOPS implementations on the main actor.
        keepAwake = KeepAwakeModel(
            userDefaults: userDefaults,
            service: sleepAssertionService,
            lidCloseService: lidCloseService,
            powerSourceMonitor: powerSourceMonitor
        )

    }

    var menuBarTitle: String {
        let segments = visibleMenuBarTitles
        guard !segments.isEmpty else { return Strings.metricsPlaceholder() }
        return segments.joined(separator: "  ")
    }

    var visibleMenuBarTitles: [String] {
        var titles: [String] = []
        let showLabel = metrics.display.identifierStyle == .labels

        if metrics.visibility.showCPU {
            titles.append(CPUFormatter.menuBarTitle(for: metrics.latestSample, showLabel: showLabel))
        }

        if metrics.visibility.showGPU {
            titles.append(GPUFormatter.menuBarTitle(for: metrics.latestGPUSample, showLabel: showLabel))
        }

        if metrics.visibility.showRAM {
            titles.append(RAMFormatter.menuBarTitle(for: metrics.latestRAMSample, showLabel: showLabel))
        }

        if metrics.visibility.showNetwork {
            titles.append(NetworkFormatter.stableMenuBarTitle(for: metrics.latestNetworkSample, showLabel: showLabel))
        }

        if metrics.visibility.showDisk {
            titles.append(DiskFormatter.stableMenuBarTitle(for: metrics.latestDiskSample, metric: metrics.display.diskMenuBarMetric, showLabel: showLabel))
        }

        if metrics.visibility.showTemperature {
            titles.append(TemperatureFormatter.menuBarTitle(for: metrics.latestTemperatureSample, showLabel: showLabel))
        }

        // Battery omits its segment when no battery is present (sample stays nil), so a
        // desktop Mac never shows it even with the toggle on (ADR-003).
        if metrics.visibility.showBattery, metrics.latestBatterySample != nil {
            titles.append(BatteryFormatter.menuBarTitle(for: metrics.latestBatterySample, showLabel: showLabel))
        }

        return titles
    }

    var accessibilityMenuBarTitle: String {
        var segments: [String] = []

        if metrics.visibility.showCPU {
            segments.append("CPU \(CPUFormatter.percentageString(metrics.latestSample?.totalUsagePercent))")
        }

        if metrics.visibility.showGPU {
            segments.append("\(Strings.gpu()) \(GPUFormatter.percentageString(for: metrics.latestGPUSample))")
        }

        if metrics.visibility.showRAM {
            segments.append("RAM \(RAMFormatter.valueString(for: metrics.latestRAMSample))")
        }

        if metrics.visibility.showNetwork {
            segments.append(NetworkFormatter.stableMenuBarTitle(for: metrics.latestNetworkSample, showLabel: true))
        }

        if metrics.visibility.showDisk {
            segments.append("\(Strings.disk()) \(DiskFormatter.stableMenuBarTitle(for: metrics.latestDiskSample, metric: metrics.display.diskMenuBarMetric, showLabel: false))")
        }

        if metrics.visibility.showTemperature {
            segments.append("\(Strings.temperature()) \(TemperatureFormatter.displayString(for: metrics.latestTemperatureSample))")
        }

        if metrics.visibility.showBattery, metrics.latestBatterySample != nil {
            segments.append("\(Strings.battery()) \(BatteryFormatter.menuBarValue(for: metrics.latestBatterySample))")
        }

        guard !segments.isEmpty else { return Strings.metricsPlaceholder() }
        return segments.joined(separator: ", ")
    }

    // MARK: - Cleaning lock + Accessibility recovery (forwards to `CleaningLockModel`, task-004)

    /// Lower-frequency read/write shims for non-reactive call sites (`StatusItemController`,
    /// `AppDelegate`). UI that needs live reactivity observes `lock` directly instead.
    func selectLockDuration(_ duration: TimeInterval) {
        lock.selectDuration(duration)
    }

    func startCleaningLock() {
        lock.start()
    }

    func refreshAccessibilityAuthorization() {
        lock.refreshAuthorizationIfEnabled()
    }

    func requestAccessibilityAccess() {
        lock.recovery.requestAccess()
    }

    func beginAccessibilityRecovery() {
        lock.recovery.beginRecovery()
    }

    func cancelAccessibilityRecovery() {
        lock.recovery.cancelRecovery()
    }

    func pollAccessibilityRecovery() {
        lock.recovery.pollRecovery()
    }

    func evaluateAccessibilityLaunchNudge() {
        lock.evaluateLaunchNudgeIfEnabled()
    }

    /// Called by AppDelegate each tick and on session end to keep the UI in sync.
    func updateLockState(phase: LockPhase, remaining: TimeInterval) {
        lock.updateState(phase: phase, remaining: remaining)
    }

    // MARK: - Update

    /// Publishes the newest available version (or `nil` when up to date). Called
    /// on the main actor by AppDelegate from the passive update probe.
    func setAvailableUpdateVersion(_ version: String?) {
        availableUpdateVersion = version
    }

    /// Fires a user-initiated update check; AppDelegate owns the updater.
    func checkForUpdates() {
        onCheckForUpdates?()
    }
}
