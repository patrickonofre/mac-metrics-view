import Foundation
import Combine

/// Where the cleaning-permission recovery flow is, for the UI to render and for the
/// state machine to gate its probe poll loop and one-shot relaunch (see ADR-002).
enum AccessibilityRecoveryPhase: Equatable {
    /// Not recovering — no probing happens.
    case idle
    /// Settings opened; the probe poll loop is running, watching for a valid grant.
    case awaitingGrant
    /// A valid grant was detected; the relaunch that applies it is in flight.
    case applying
}

@MainActor
final class CPUState: ObservableObject {
    @Published private(set) var visibility: MetricVisibilitySettings
    @Published private(set) var display: MetricDisplaySettings
    @Published private(set) var updateRate: Int
    @Published private(set) var latestSample: CPUSample?
    @Published private(set) var latestRAMSample: RAMSample?
    @Published private(set) var latestNetworkSample: NetworkSample?
    @Published private(set) var latestTemperatureSample: TemperatureSample?
    @Published private(set) var latestDiskSample: DiskSample?
    @Published private(set) var latestGPUSample: GPUSample?
    /// Latest battery reading, or `nil` when no battery is present / not yet sampled.
    /// No history is kept (ADR-002 — no charge sparkline).
    @Published private(set) var latestBatterySample: BatterySample?
    /// The Ambient pillar (TD-012): the latest ambient-light reading, the derived theme
    /// suggestion, and the opt-in settings. Extracted to `AmbientThemeModel` (task-003).
    /// `PopoverView` observes `ambient` directly (its own `@ObservedObject`) because, unlike
    /// the menu bar, the theme-suggestion banner has no AppKit-imperative refresh path —
    /// it only exists in SwiftUI, so it must react to the model's own publisher. Lower-
    /// frequency consumers (Settings tab, AppDelegate's sampler gate) read through the
    /// `ambientThemeSettings`/`latestAmbientSample` shims below instead.
    let ambient: AmbientThemeModel
    @Published private(set) var topCPUProcesses: [ProcessCPUSample] = []
    @Published private(set) var history = CPUHistory()
    @Published private(set) var ramHistory = RAMHistory()
    @Published private(set) var networkHistory = NetworkHistory()
    @Published private(set) var temperatureHistory = TemperatureHistory()
    @Published private(set) var diskHistory = DiskHistory()
    @Published private(set) var gpuHistory = GPUHistory()

    /// Cumulative download/upload and read/write byte totals since launch (in-memory,
    /// reset each launch), folded from consecutive sample gaps. Surface the since-launch
    /// rows in the expanded network/disk cards, distinct from the ~45s window stats.
    @Published private(set) var networkSessionTotals = TrafficSessionTotals()
    @Published private(set) var diskSessionTotals = TrafficSessionTotals()
    private var lastNetworkSampleTimestamp: Date?
    private var lastDiskSampleTimestamp: Date?

    /// The Dev/AI pillar (TD-012): token stores, the derived aggregate/cost/burn-rate/
    /// rate-limit surfaces, the daily ledger and the popover-open refresh (ADR-005).
    /// Extracted to `TokenUsageModel` (task-001/002). Deliberately **not** bridged to this
    /// coordinator's `objectWillChange`: `StatusItemController` is AppKit-imperative and
    /// learns about token changes via an explicit `setNeedsTitleUpdate()` push from
    /// `AppDelegate.tokenUsageSampler(_:didProduce:)`, never through Combine. SwiftUI
    /// consumers that need live token reactivity observe `token` directly at the point of
    /// use (e.g. `MetricsTab`) — bridging here would re-invalidate every `CPUState`
    /// observer (Settings/Actions tabs) on every token tick, including the popover-open
    /// 30s auto-refresh (ADR-005), defeating the churn isolation this split exists for.
    let token: TokenUsageModel

    /// Interval the disk sampler ticks at, used to convert rolling-window rate
    /// sums into byte totals for the popover (see DiskWindowStats / ADR-002).
    let diskSampleInterval: TimeInterval = 1

    // Cleaning-lock state — updated by AppDelegate via updateLockState(phase:remaining:)
    @Published private(set) var lockPhase: LockPhase = .idle
    @Published private(set) var lockRemaining: TimeInterval = 0
    @Published private(set) var cleaningLockSettings: CleaningLockSettings

    /// Newest version announced by the appcast when it is more recent than the
    /// installed build, or `nil` when the app is up to date. Fed by a passive
    /// Sparkle probe (no dialog) via `setAvailableUpdateVersion(_:)`.
    @Published private(set) var availableUpdateVersion: String?

    /// Live Accessibility (AX) permission gate for the cleaning lock.
    /// Refreshed on each popover show so a grant made in System Settings is
    /// reflected without relaunching the app.
    @Published private(set) var isAccessibilityGranted: Bool = false

    /// True when AX is not currently granted but a *previous* app version had
    /// it — i.e. an update reset the permission (ad-hoc signing, TD-010). The UI
    /// uses this to tell the user the stale System Settings entry must be removed
    /// and re-added, not merely toggled.
    @Published private(set) var accessibilityResetByUpdate: Bool = false

    /// Where the self-healing recovery flow is. Drives the popover's recovery card
    /// (awaiting vs applying) and gates the probe poll loop: probing happens only
    /// while `.awaitingGrant`.
    @Published private(set) var recoveryPhase: AccessibilityRecoveryPhase = .idle

    /// Tracks if the popover is currently open. Used to lazy-load PopoverView content
    /// and completely bypass SwiftUI view graph updates when the popover is closed.
    @Published var isPopoverOpen: Bool = false {
        didSet {
            if oldValue != isPopoverOpen {
                onPopoverOpenChange?(isPopoverOpen)
            }
        }
    }


    var onVisibilityChange: ((MetricVisibilitySettings.Metric, Bool) -> Void)?
    var onDisplayChange: (() -> Void)?
    var onPopoverOpenChange: ((Bool) -> Void)?
    /// Called by the UI when the user taps Iniciar; AppDelegate wires the actual lock start.
    var onStartLock: ((TimeInterval) -> Void)?
    /// Called when the user requests a manual update check; AppDelegate forwards to the updater.
    var onCheckForUpdates: (() -> Void)?
    /// Called when the user asks to relaunch after granting Accessibility; AppDelegate owns the relaunch.
    var onRelaunch: (() -> Void)?
    /// Asks the UI to open the popover programmatically (for the one-time post-update
    /// nudge). AppDelegate wires this to `StatusItemController.openPopover()`.
    var onRequestOpenPopover: (() -> Void)?
    /// Fires when the ambient theme settings change so AppDelegate can start/stop the
    /// ambient sampler in step with the opt-in flag.
    var onAmbientThemeSettingsChange: ((AmbientThemeSettings) -> Void)?

    private let userDefaults: UserDefaults
    private let accessibilityAuthorization: AccessibilityAuthorizationProtocol
    private let accessibilityProbe: AccessibilityProbing
    private let currentAppVersion: String
    private var grantTracker: AccessibilityGrantTracker
    /// One-time auto-open nudge persistence (fires once per reset event).
    private var nudgeTracker: AccessibilityNudgeTracker
    /// Active only while `recoveryPhase == .awaitingGrant`; spawns a probe each tick.
    private var recoveryPollTimer: Timer?
    private let processReader: ProcessReading
    /// Runs the all-PID process enumeration off the main thread (PERF-01). The reader's mutable
    /// state (its PID→name cache) is touched only inside the executor; `previousProcessSnapshot`
    /// stays main-confined and is read/written only in the main-actor delivery closure.
    private let samplingExecutor: SamplingExecutor
    private var previousProcessSnapshot: ProcessCPUSnapshot?
    private var processSamplingTimer: Timer?
    /// Probe cadence during recovery. Slow enough to stay cheap (a process spawn per
    /// tick), fast enough that re-adding the entry is noticed promptly.
    private let recoveryPollInterval: TimeInterval = 1.5
    /// True once the native AX prompt has been shown this session. macOS only
    /// surfaces that prompt once per launch, so later taps fall back to opening
    /// the Settings pane directly instead of doing nothing.
    private var hasPromptedForAccess = false
    /// Snapshot of the tracker as it was *before this launch* recorded the
    /// current version. Reset detection is computed against this frozen baseline
    /// so the flag stays stable across in-session refreshes — once the current
    /// version is recorded as "seen", the live tracker would no longer report a
    /// reset, but the user still needs the recovery guidance until they grant.
    private let resetBaselineTracker: AccessibilityGrantTracker
    /// One-shot battery reader used to refresh the popover row on open, so the popover
    /// shows live battery data like every other metric even while the menu-bar segment
    /// is hidden and the continuous sampler is gated off (ADR-003). Returns nil on Macs
    /// with no battery, so `latestBatterySample` stays nil → "no battery" row.
    private let batteryReader: BatteryReading

    init(
        userDefaults: UserDefaults = .standard,
        accessibilityAuthorization: AccessibilityAuthorizationProtocol = SystemAccessibilityAuthorization(),
        accessibilityProbe: AccessibilityProbing? = nil,
        batteryReader: BatteryReading = IOKitBatteryReader(),
        systemAppearance: SystemAppearanceControlling? = nil,
        processReader: ProcessReading = LibprocProcessReader(),
        samplingExecutor: SamplingExecutor = BackgroundSamplingExecutor(),
        currentAppVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    ) {
        self.processReader = processReader
        self.samplingExecutor = samplingExecutor
        self.userDefaults = userDefaults
        self.batteryReader = batteryReader
        ambient = AmbientThemeModel(
            userDefaults: userDefaults,
            systemAppearance: systemAppearance ?? SystemAppearanceController()
        )
        self.accessibilityAuthorization = accessibilityAuthorization
        // `SystemAccessibilityProbe` is `@MainActor`, so it cannot be a default
        // argument (those are evaluated in a nonisolated context); build it here in
        // the main-actor init instead. Tests inject a `FakeAccessibilityProbe`.
        self.accessibilityProbe = accessibilityProbe ?? SystemAccessibilityProbe()
        self.currentAppVersion = currentAppVersion
        let loadedTracker = AccessibilityGrantTracker.load(from: userDefaults)
        grantTracker = loadedTracker
        resetBaselineTracker = loadedTracker
        nudgeTracker = AccessibilityNudgeTracker.load(from: userDefaults)
        visibility = MetricVisibilitySettings.load(from: userDefaults)
        let loadedDisplay = MetricDisplaySettings.resolved(from: userDefaults)
        display = loadedDisplay
        updateRate = loadedDisplay.updateRate
        cleaningLockSettings = CleaningLockSettings.load(from: userDefaults)

        token = TokenUsageModel(
            userDefaults: userDefaults,
            selection: TokenDisplaySelection(
                scope: loadedDisplay.tokenScope,
                window: loadedDisplay.tokenMenuBarWindow,
                provider: loadedDisplay.tokenProvider,
                sessionBudget: loadedDisplay.tokenSessionBudget,
                weeklyBudget: loadedDisplay.tokenWeeklyBudget
            )
        )

        evaluateAccessibility()
    }

    deinit {
        // No leaked timers if the state is torn down mid-recovery or popover-open.
        recoveryPollTimer?.invalidate()
        processSamplingTimer?.invalidate()
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

        if visibility.showGPU {
            titles.append(GPUFormatter.menuBarTitle(for: latestGPUSample, showLabel: showLabel))
        }

        if visibility.showRAM {
            titles.append(RAMFormatter.menuBarTitle(for: latestRAMSample, metric: display.ramMenuBarMetric, showLabel: showLabel))
        }

        if visibility.showNetwork {
            titles.append(NetworkFormatter.stableMenuBarTitle(for: latestNetworkSample, showLabel: showLabel))
        }

        if visibility.showDisk {
            titles.append(DiskFormatter.stableMenuBarTitle(for: latestDiskSample, metric: display.diskMenuBarMetric, showLabel: showLabel))
        }

        if visibility.showTemperature {
            titles.append(TemperatureFormatter.menuBarTitle(for: latestTemperatureSample, showLabel: showLabel))
        }

        // Battery omits its segment when no battery is present (sample stays nil), so a
        // desktop Mac never shows it even with the toggle on (ADR-003).
        if visibility.showBattery, latestBatterySample != nil {
            titles.append(BatteryFormatter.menuBarTitle(for: latestBatterySample, showLabel: showLabel))
        }

        if visibility.showTokens {
            let value = TokenFormatter.menuBarTitle(for: token.aggregate, showLabel: false)
            if showLabel {
                titles.append("\(TokenFormatter.menuBarLabel(for: display.tokenProvider)) \(value)")
            } else {
                titles.append(value)
            }
        }

        return titles
    }

    var menuBarTextStyle: CPUMenuBarTextStyle {
        CPUFormatter.menuBarTextStyle(for: latestSample)
    }

    var ramMenuBarTextStyle: CPUMenuBarTextStyle {
        RAMFormatter.menuBarTextStyle(for: latestRAMSample, metric: display.ramMenuBarMetric)
    }

    var ramMenuBarMetric: MetricDisplaySettings.RAMMenuBarMetric {
        display.ramMenuBarMetric
    }

    /// Popover RAM card headline: "Used / Total" — more honest than echoing the menu-bar
    /// metric, since it shows how much of total memory is actually in use.
    var ramCardValue: String {
        RAMFormatter.usedTotalString(used: latestRAMSample?.usedGB, total: latestRAMSample?.totalGB)
    }

    /// Activity-Monitor-style breakdown rows for the expanded RAM card.
    var ramDetailRows: [(label: String, value: String)] {
        RAMFormatter.detailRows(for: latestRAMSample)
    }

    /// Rolling-window download/upload totals and peaks for the expanded network card.
    /// Integrates the retained rates over the configured sampling interval (ADR-002).
    var networkDetailRows: [(label: String, value: String)] {
        NetworkFormatter.detailRows(
            history: networkHistory,
            interval: TimeInterval(updateRate),
            session: networkSessionTotals
        )
    }

    /// Rolling-window read/write totals and peaks for the expanded disk card.
    /// Integrates the retained rates over the configured sampling interval (ADR-002).
    var diskDetailRows: [(label: String, value: String)] {
        DiskFormatter.detailRows(
            history: diskHistory,
            interval: TimeInterval(updateRate),
            session: diskSessionTotals
        )
    }

    var temperatureMenuBarTextStyle: CPUMenuBarTextStyle {
        TemperatureFormatter.menuBarTextStyle(for: latestTemperatureSample)
    }

    var diskMenuBarTextStyle: CPUMenuBarTextStyle {
        DiskFormatter.menuBarTextStyle(for: latestDiskSample)
    }

    var gpuMenuBarTextStyle: CPUMenuBarTextStyle {
        GPUFormatter.menuBarTextStyle(for: latestGPUSample)
    }

    /// Popover GPU card headline: the utilization percentage, or `--%` until the first read.
    var gpuCardValue: String {
        GPUFormatter.percentageString(for: latestGPUSample)
    }

    var batteryMenuBarTextStyle: CPUMenuBarTextStyle {
        BatteryFormatter.menuBarTextStyle(for: latestBatterySample)
    }

    /// Popover headline for the battery row: the charge percentage, or the localized
    /// "no battery" copy on a Mac without one.
    var batteryRowValue: String {
        latestBatterySample == nil ? Strings.batteryNoBattery() : BatteryFormatter.menuBarValue(for: latestBatterySample)
    }

    /// SF Symbol shown next to the battery row (charge-level glyph, bolt while charging).
    var batterySymbolName: String {
        BatteryFormatter.menuBarGlyphName(for: latestBatterySample)
    }

    /// Power source / time / health / cycle detail rows, empty when no battery present.
    var batteryDetailRows: [(label: String, value: String)] {
        BatteryFormatter.detailRows(for: latestBatterySample)
    }

    var diskMenuBarMetric: MetricDisplaySettings.DiskMenuBarMetric {
        display.diskMenuBarMetric
    }

    var tokenScope: TokenScope {
        display.tokenScope
    }

    var tokenMenuBarWindow: TokenWindow {
        display.tokenMenuBarWindow
    }

    /// The selected provider (Claude / Codex / Combined) the meter currently shows.
    var tokenProvider: TokenProviderSelection {
        display.tokenProvider
    }

    /// The token-relevant slice of `display`, pushed into the model on each picker change.
    private var tokenSelection: TokenDisplaySelection {
        TokenDisplaySelection(
            scope: display.tokenScope,
            window: display.tokenMenuBarWindow,
            provider: display.tokenProvider,
            sessionBudget: display.tokenSessionBudget,
            weeklyBudget: display.tokenWeeklyBudget
        )
    }

    var hasVisibleMetric: Bool {
        visibility.hasVisibleMetric
    }

    var accessibilityMenuBarTitle: String {
        var segments: [String] = []

        if visibility.showCPU {
            segments.append("CPU \(CPUFormatter.percentageString(latestSample?.totalUsagePercent))")
        }

        if visibility.showGPU {
            segments.append("\(Strings.gpu()) \(GPUFormatter.percentageString(for: latestGPUSample))")
        }

        if visibility.showRAM {
            segments.append("RAM \(RAMFormatter.valueString(for: latestRAMSample, metric: display.ramMenuBarMetric))")
        }

        if visibility.showNetwork {
            segments.append(NetworkFormatter.stableMenuBarTitle(for: latestNetworkSample, showLabel: true))
        }

        if visibility.showDisk {
            segments.append("\(Strings.disk()) \(DiskFormatter.stableMenuBarTitle(for: latestDiskSample, metric: display.diskMenuBarMetric, showLabel: false))")
        }

        if visibility.showTemperature {
            segments.append("\(Strings.temperature()) \(TemperatureFormatter.displayString(for: latestTemperatureSample))")
        }

        if visibility.showBattery, latestBatterySample != nil {
            segments.append("\(Strings.battery()) \(BatteryFormatter.menuBarValue(for: latestBatterySample))")
        }

        if visibility.showTokens {
            segments.append("\(Strings.tokens()) \(TokenFormatter.menuBarTitle(for: token.aggregate, showLabel: false))")
        }

        guard !segments.isEmpty else { return Strings.metricsPlaceholder() }
        return segments.joined(separator: ", ")
    }

    // Samples are always recorded, independent of menu-bar visibility: the popover shows
    // every metric, while `visibility` only curates which ones appear in the menu bar.
    func update(with sample: CPUSample) {
        latestSample = sample
        history.append(sample)
    }

    func update(with sample: RAMSample) {
        latestRAMSample = sample
        ramHistory.append(sample)
    }

    func update(with sample: NetworkSample) {
        latestNetworkSample = sample
        networkHistory.append(sample)
        if let last = lastNetworkSampleTimestamp {
            networkSessionTotals.add(
                inboundRate: sample.downloadBytesPerSecond,
                outboundRate: sample.uploadBytesPerSecond,
                elapsed: sample.timestamp.timeIntervalSince(last)
            )
        }
        lastNetworkSampleTimestamp = sample.timestamp
    }

    func update(with sample: TemperatureSample) {
        latestTemperatureSample = sample
        temperatureHistory.append(sample)
    }

    func update(with sample: DiskSample) {
        latestDiskSample = sample
        diskHistory.append(sample)
        if let last = lastDiskSampleTimestamp {
            diskSessionTotals.add(
                inboundRate: sample.readBytesPerSecond,
                outboundRate: sample.writeBytesPerSecond,
                elapsed: sample.timestamp.timeIntervalSince(last)
            )
        }
        lastDiskSampleTimestamp = sample.timestamp
    }

    func update(with sample: GPUSample) {
        latestGPUSample = sample
        gpuHistory.append(sample)
    }

    /// No history is kept for battery (ADR-002 — no charge sparkline); just the latest.
    func update(with sample: BatterySample) {
        latestBatterySample = sample
    }

    /// One-shot battery read used when the popover opens, so the battery row shows live
    /// data even when the menu-bar segment is hidden (its continuous sampler is gated off
    /// while hidden, ADR-003). A nil read (no battery hardware) leaves the row as
    /// "no battery"; it never clears a previously good sample.
    func refreshBatteryReading() {
        if let sample = batteryReader.readSample() {
            latestBatterySample = sample
        }
    }

    // MARK: - Ambient theme suggestion (forwards to `AmbientThemeModel`, task-003)

    /// Lower-frequency read shims (Settings tab, AppDelegate's sampler gate). The
    /// reactive banner in `PopoverView` observes `ambient` directly instead.
    var ambientThemeSettings: AmbientThemeSettings { ambient.settings }
    var latestAmbientSample: AmbientLightSample? { ambient.latestSample }
    var themeSuggestion: ThemeSuggestion { ambient.suggestion }
    var lastAppearanceApplyResult: AppearanceApplyResult? { ambient.lastApplyResult }

    func update(with sample: AmbientLightSample) {
        ambient.update(with: sample)
    }

    func applyThemeSuggestion() {
        ambient.apply()
    }

    func dismissThemeSuggestion() {
        ambient.dismiss()
    }

    /// Persists new ambient settings via the model and fires the change callback so
    /// `AppDelegate` can start/stop the sampler in step with the opt-in flag.
    func setAmbientThemeSettings(_ settings: AmbientThemeSettings) {
        guard ambient.setSettings(settings) else { return }
        onAmbientThemeSettingsChange?(settings)
    }

    /// Forwards token ingest to the model (task-001 shim).
    func update(provider: TokenProvider, with events: [TokenUsageEvent]) {
        token.update(provider: provider, with: events)
    }

    /// Claude-provider convenience used by the existing Claude sampler path and tests.
    func update(with events: [TokenUsageEvent]) {
        token.update(with: events)
    }

    func setTokenVisible(_ isVisible: Bool) {
        updateVisibility(metric: .tokens, isVisible: isVisible)
    }

    func setTokenScope(_ scope: TokenScope) {
        guard display.tokenScope != scope else { return }

        display.tokenScope = scope
        display.save(to: userDefaults)
        token.apply(selection: tokenSelection)
        onDisplayChange?()
    }

    func setTokenMenuBarWindow(_ window: TokenWindow) {
        guard display.tokenMenuBarWindow != window else { return }

        display.tokenMenuBarWindow = window
        display.save(to: userDefaults)
        token.apply(selection: tokenSelection)
        onDisplayChange?()
    }

    /// Switches the displayed provider (Claude / Codex / Combined), persists it, and
    /// republishes every token-derived surface from the already-ingested stores.
    func setTokenProvider(_ selection: TokenProviderSelection) {
        guard display.tokenProvider != selection else { return }

        display.tokenProvider = selection
        display.save(to: userDefaults)
        token.apply(selection: tokenSelection)
        onDisplayChange?()
    }

    /// Persists the 5h-block token budget (0 = off, negatives clamp to 0 —
    /// ADR-008) and republishes the snapshot so the bar appears immediately.
    func setTokenSessionBudget(_ budget: Int) {
        let sanitized = max(0, budget)
        guard display.tokenSessionBudget != sanitized else { return }

        display.tokenSessionBudget = sanitized
        display.save(to: userDefaults)
        token.apply(selection: tokenSelection)
    }

    /// Persists the weekly token budget (0 = off, negatives clamp to 0 — ADR-008).
    func setTokenWeeklyBudget(_ budget: Int) {
        let sanitized = max(0, budget)
        guard display.tokenWeeklyBudget != sanitized else { return }

        display.tokenWeeklyBudget = sanitized
        display.save(to: userDefaults)
        token.apply(selection: tokenSelection)
    }

    /// Forwards the since-reset counter restart to the model (task-001 shim).
    func resetTokenCounter() {
        token.resetCounter()
    }

    /// Forwards the popover-open token refresh lifecycle to the model (ADR-005 shims).
    func beginTokenAutoRefresh() {
        token.beginAutoRefresh()
    }

    func endTokenAutoRefresh() {
        token.endAutoRefresh()
    }

    func tokenAutoRefreshTick(now: Date = Date()) {
        token.autoRefreshTick(now: now)
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

    func setDiskVisible(_ isVisible: Bool) {
        updateVisibility(metric: .disk, isVisible: isVisible)
    }

    func setBatteryVisible(_ isVisible: Bool) {
        updateVisibility(metric: .battery, isVisible: isVisible)
    }

    func setGPUVisible(_ isVisible: Bool) {
        updateVisibility(metric: .gpu, isVisible: isVisible)
    }

    func setMetricIdentifierStyle(_ identifierStyle: MetricDisplaySettings.IdentifierStyle) {
        guard display.identifierStyle != identifierStyle else { return }

        display.identifierStyle = identifierStyle
        display.save(to: userDefaults)
        onDisplayChange?()
    }

    func setUpdateRate(_ rate: Int) {
        let clamped = (rate == 1 || rate == 2 || rate == 3) ? rate : 1
        display.updateRate = clamped
        display.save(to: userDefaults)
        updateRate = clamped
        onDisplayChange?()
    }

    func setRAMMenuBarMetric(_ metric: MetricDisplaySettings.RAMMenuBarMetric) {
        guard display.ramMenuBarMetric != metric else { return }

        display.ramMenuBarMetric = metric
        display.save(to: userDefaults)
        onDisplayChange?()
    }

    func setDiskMenuBarMetric(_ metric: MetricDisplaySettings.DiskMenuBarMetric) {
        guard display.diskMenuBarMetric != metric else { return }

        display.diskMenuBarMetric = metric
        display.save(to: userDefaults)
        onDisplayChange?()
    }

    private func updateVisibility(metric: MetricVisibilitySettings.Metric, isVisible: Bool) {
        guard currentVisibility(for: metric) != isVisible else { return }

        // Toggling only curates the menu bar. Samplers keep running and history keeps
        // accumulating, so there is no stale data to reset on re-show.
        switch metric {
        case .cpu:
            visibility.showCPU = isVisible
        case .ram:
            visibility.showRAM = isVisible
        case .network:
            visibility.showNetwork = isVisible
        case .temperature:
            visibility.showTemperature = isVisible
        case .disk:
            visibility.showDisk = isVisible
        case .tokens:
            visibility.showTokens = isVisible
        case .battery:
            visibility.showBattery = isVisible
        case .gpu:
            visibility.showGPU = isVisible
        }

        visibility.save(to: userDefaults)
        onVisibilityChange?(metric, isVisible)
    }

    // MARK: - Process Sampling

    func beginProcessSampling() {
        guard processSamplingTimer == nil else { return } // idempotent
        // Baseline read runs off the main thread (PERF-01); the snapshot is stored on the
        // main actor. The first tick is a no-op until it lands (guarded on a nil baseline).
        samplingExecutor.run({ [processReader] in processReader.readSnapshot() }) { [weak self] snapshot in
            self?.previousProcessSnapshot = snapshot
        }
        processSamplingTimer = MainRunLoopTimer.repeating(every: 2) { [weak self] in
            self?.processSamplingTick()
        }
    }

    func endProcessSampling() {
        processSamplingTimer?.invalidate()
        processSamplingTimer = nil
        previousProcessSnapshot = nil
    }

    func processSamplingTick(now: Date = Date()) {
        guard processSamplingTimer != nil, let prev = previousProcessSnapshot else { return }
        // Enumerate all PIDs off the main thread (PERF-01); rank and publish on the main actor.
        // Re-check the timer in the delivery closure so a stop() between read and delivery
        // cannot publish a late ranking.
        samplingExecutor.run({ [processReader] in processReader.readSnapshot() }) { [weak self] cur in
            guard let self, self.processSamplingTimer != nil, let cur else { return }
            self.topCPUProcesses = ProcessCPURanking.topProcesses(previous: prev, current: cur)
            self.previousProcessSnapshot = cur
        }
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
        evaluateAccessibility()
    }

    /// User-initiated request for the Accessibility grant. The first tap shows
    /// the native macOS prompt (which registers the entry under the running
    /// build's identity); later taps open the Settings pane directly, since the
    /// system prompt only appears once per launch.
    func requestAccessibilityAccess() {
        if hasPromptedForAccess {
            accessibilityAuthorization.openSettings()
        } else {
            hasPromptedForAccess = true
            accessibilityAuthorization.promptForAccess()
            accessibilityAuthorization.openSettings()
        }
    }

    // MARK: - Self-healing recovery

    /// Starts active recovery: opens the Accessibility pane and begins polling a
    /// fresh child-process probe for the *current* code identity's grant (the
    /// in-process `AXIsProcessTrusted()` stays stale, ADR-002). On the first trusted
    /// result the app relaunches to apply the grant.
    func beginAccessibilityRecovery() {
        guard recoveryPhase == .idle else { return }
        recoveryPhase = .awaitingGrant
        // Reuses the request path: the first call shows the native prompt, which
        // registers the entry under the *running build's* identity (avoiding the
        // stale-entry trap), and opens the Accessibility pane. Later calls just
        // open Settings. The probe loop then watches for the re-added grant.
        requestAccessibilityAccess()
        startRecoveryPolling()
    }

    /// Stops active recovery (e.g. the popover was dismissed before a grant) and
    /// tears down the poll loop, returning to `.idle`.
    func cancelAccessibilityRecovery() {
        guard recoveryPhase == .awaitingGrant else { return }
        stopRecoveryPolling()
        recoveryPhase = .idle
    }

    /// One poll tick: spawn a fresh probe and apply its result. Internal (not
    /// private) so the unit tests can drive ticks deterministically, the same way
    /// `FakeInputLockService.tick()` drives the lock tests. A no-op outside active
    /// recovery, so a late timer fire after cancel cannot spawn a probe.
    func pollAccessibilityRecovery() {
        guard recoveryPhase == .awaitingGrant else { return }
        accessibilityProbe.probe { [weak self] trusted in
            self?.handleProbeResult(trusted)
        }
    }

    /// One-time launch decision: when an update reset the grant and the proactive
    /// nudge has not yet fired for this version, ask the UI to open the recovery
    /// card once, recording the nudge so it never repeats for this version (ADR-003).
    func evaluateAccessibilityLaunchNudge() {
        guard !isAccessibilityGranted else { return }
        guard accessibilityResetByUpdate else { return }
        guard nudgeTracker.shouldNudge(forVersion: currentAppVersion) else { return }
        nudgeTracker = nudgeTracker.recordingNudge(version: currentAppVersion)
        nudgeTracker.save(to: userDefaults)
        onRequestOpenPopover?()
    }

    private func handleProbeResult(_ trusted: Bool) {
        // Ignore a result that lands after cancel or after applying already began —
        // relaunch fires at most once, only during active recovery.
        guard recoveryPhase == .awaitingGrant, trusted else { return }
        recoveryPhase = .applying
        stopRecoveryPolling()
        onRelaunch?()
    }

    private func startRecoveryPolling() {
        stopRecoveryPolling()
        recoveryPollTimer = MainRunLoopTimer.repeating(every: recoveryPollInterval) { [weak self] in
            self?.pollAccessibilityRecovery()
        }
    }

    private func stopRecoveryPolling() {
        recoveryPollTimer?.invalidate()
        recoveryPollTimer = nil
    }

    /// Reads the live AX permission, publishes the gate, and maintains the
    /// grant tracker so an update-reset state can be told apart from a normal
    /// first-time grant. When trusted, records the current version as the last
    /// granted one; when not, flags whether an earlier version had been granted.
    private func evaluateAccessibility() {
        let trusted = accessibilityAuthorization.isTrusted
        isAccessibilityGranted = trusted

        if trusted {
            accessibilityResetByUpdate = false
            if grantTracker.lastGrantedVersion != currentAppVersion {
                grantTracker = grantTracker.recordingGrant(version: currentAppVersion)
                grantTracker.save(to: userDefaults)
            }
        } else {
            // Compare against the pre-launch baseline so the flag does not flip
            // off once this version is recorded as seen below.
            accessibilityResetByUpdate = resetBaselineTracker.wasResetByUpdate(
                isTrusted: false,
                currentVersion: currentAppVersion
            )
            // Remember that this build ran (even ungranted), so a *future*
            // update can be recognised as a reset for never-granted users too.
            if grantTracker.lastSeenVersion != currentAppVersion {
                grantTracker = grantTracker.recordingSeen(version: currentAppVersion)
                grantTracker.save(to: userDefaults)
            }
        }
    }

    /// Called by AppDelegate each tick and on session end to keep the UI in sync.
    func updateLockState(phase: LockPhase, remaining: TimeInterval) {
        lockPhase = phase
        lockRemaining = remaining
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
        case .disk:
            return visibility.showDisk
        case .tokens:
            return visibility.showTokens
        case .battery:
            return visibility.showBattery
        case .gpu:
            return visibility.showGPU
        }
    }
}
