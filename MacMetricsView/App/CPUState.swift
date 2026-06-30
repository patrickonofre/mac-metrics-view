import Foundation
import Combine

@MainActor
final class CPUState: ObservableObject {
    /// The System metrics pillar (TD-012): CPU/RAM/network/disk/temperature/battery/GPU
    /// samples, history, and visibility/display settings. Extracted to `SystemMetricsModel`
    /// (task-005) — like `token`, `StatusItemController` reads it imperatively (no
    /// observation needed; `AppDelegate`'s sampler delegates push `setNeedsTitleUpdate()`).
    /// SwiftUI consumers (`MetricsTab`, `SettingsTab`) observe `metrics` directly.
    let metrics: SystemMetricsModel

    /// The Ambient pillar (TD-012): the latest ambient-light reading, the derived theme
    /// suggestion, and the opt-in settings. Extracted to `AmbientThemeModel` (task-003).
    /// `PopoverView` observes `ambient` directly (its own `@ObservedObject`) because, unlike
    /// the menu bar, the theme-suggestion banner has no AppKit-imperative refresh path —
    /// it only exists in SwiftUI, so it must react to the model's own publisher.
    let ambient: AmbientThemeModel

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

    /// The Utilities pillar (TD-012): cleaning-mode input lock + the Accessibility
    /// recovery flow that gates it. Extracted to `CleaningLockModel` (task-004), which
    /// composes `AccessibilityRecoveryModel` and bridges its changes internally. UI
    /// observes `lock` directly at the point of use (`ActionsTab`, `LockOverlayView`,
    /// `PopoverView`'s recovery banner) — same no-upward-bridge contract as `token`/`ambient`.
    let lock: CleaningLockModel

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


    var onPopoverOpenChange: ((Bool) -> Void)?
    /// Called when the user requests a manual update check; AppDelegate forwards to the updater.
    var onCheckForUpdates: (() -> Void)?
    /// Fires when the ambient theme settings change so AppDelegate can start/stop the
    /// ambient sampler in step with the opt-in flag.
    var onAmbientThemeSettingsChange: ((AmbientThemeSettings) -> Void)?

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
        systemAppearance: SystemAppearanceControlling? = nil,
        processReader: ProcessReading = LibprocProcessReader(),
        samplingExecutor: SamplingExecutor = BackgroundSamplingExecutor(),
        currentAppVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    ) {
        self.userDefaults = userDefaults
        metrics = SystemMetricsModel(
            userDefaults: userDefaults,
            processReader: processReader,
            samplingExecutor: samplingExecutor,
            batteryReader: batteryReader
        )
        ambient = AmbientThemeModel(
            userDefaults: userDefaults,
            systemAppearance: systemAppearance ?? SystemAppearanceController()
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

        token = TokenUsageModel(
            userDefaults: userDefaults,
            selection: TokenDisplaySelection(
                scope: metrics.display.tokenScope,
                window: metrics.display.tokenMenuBarWindow,
                provider: metrics.display.tokenProvider,
                sessionBudget: metrics.display.tokenSessionBudget,
                weeklyBudget: metrics.display.tokenWeeklyBudget
            )
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
            titles.append(RAMFormatter.menuBarTitle(for: metrics.latestRAMSample, metric: metrics.display.ramMenuBarMetric, showLabel: showLabel))
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

        if metrics.visibility.showTokens {
            let value = TokenFormatter.menuBarTitle(for: token.aggregate, showLabel: false)
            if showLabel {
                titles.append("\(TokenFormatter.menuBarLabel(for: metrics.display.tokenProvider)) \(value)")
            } else {
                titles.append(value)
            }
        }

        return titles
    }

    var tokenScope: TokenScope {
        metrics.display.tokenScope
    }

    var tokenMenuBarWindow: TokenWindow {
        metrics.display.tokenMenuBarWindow
    }

    /// The selected provider (Claude / Codex / Combined) the meter currently shows.
    var tokenProvider: TokenProviderSelection {
        metrics.display.tokenProvider
    }

    /// The token-relevant slice of `metrics.display`, pushed into the model on each
    /// picker change.
    private var tokenSelection: TokenDisplaySelection {
        TokenDisplaySelection(
            scope: metrics.display.tokenScope,
            window: metrics.display.tokenMenuBarWindow,
            provider: metrics.display.tokenProvider,
            sessionBudget: metrics.display.tokenSessionBudget,
            weeklyBudget: metrics.display.tokenWeeklyBudget
        )
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
            segments.append("RAM \(RAMFormatter.valueString(for: metrics.latestRAMSample, metric: metrics.display.ramMenuBarMetric))")
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

        if metrics.visibility.showTokens {
            segments.append("\(Strings.tokens()) \(TokenFormatter.menuBarTitle(for: token.aggregate, showLabel: false))")
        }

        guard !segments.isEmpty else { return Strings.metricsPlaceholder() }
        return segments.joined(separator: ", ")
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

    /// Token picker setters mutate `metrics.display` (the persisted slice they live in)
    /// and then push the change into `token` — coordination only `CPUState` can do since
    /// it owns both models.
    func setTokenScope(_ scope: TokenScope) {
        guard metrics.display.tokenScope != scope else { return }
        var newDisplay = metrics.display
        newDisplay.tokenScope = scope
        metrics.replaceDisplay(newDisplay)
        token.apply(selection: tokenSelection)
        onDisplayChange?()
    }

    func setTokenMenuBarWindow(_ window: TokenWindow) {
        guard metrics.display.tokenMenuBarWindow != window else { return }
        var newDisplay = metrics.display
        newDisplay.tokenMenuBarWindow = window
        metrics.replaceDisplay(newDisplay)
        token.apply(selection: tokenSelection)
        onDisplayChange?()
    }

    /// Switches the displayed provider (Claude / Codex / Combined), persists it, and
    /// republishes every token-derived surface from the already-ingested stores.
    func setTokenProvider(_ selection: TokenProviderSelection) {
        guard metrics.display.tokenProvider != selection else { return }
        var newDisplay = metrics.display
        newDisplay.tokenProvider = selection
        metrics.replaceDisplay(newDisplay)
        token.apply(selection: tokenSelection)
        onDisplayChange?()
    }

    /// Persists the 5h-block token budget (0 = off, negatives clamp to 0 —
    /// ADR-008) and republishes the snapshot so the bar appears immediately.
    func setTokenSessionBudget(_ budget: Int) {
        let sanitized = max(0, budget)
        guard metrics.display.tokenSessionBudget != sanitized else { return }
        var newDisplay = metrics.display
        newDisplay.tokenSessionBudget = sanitized
        metrics.replaceDisplay(newDisplay)
        token.apply(selection: tokenSelection)
    }

    /// Persists the weekly token budget (0 = off, negatives clamp to 0 — ADR-008).
    func setTokenWeeklyBudget(_ budget: Int) {
        let sanitized = max(0, budget)
        guard metrics.display.tokenWeeklyBudget != sanitized else { return }
        var newDisplay = metrics.display
        newDisplay.tokenWeeklyBudget = sanitized
        metrics.replaceDisplay(newDisplay)
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
        lock.recovery.refreshAuthorization()
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
        lock.recovery.evaluateLaunchNudge()
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
