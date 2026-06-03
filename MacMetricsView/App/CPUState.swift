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
    @Published private(set) var latestSample: CPUSample?
    @Published private(set) var latestRAMSample: RAMSample?
    @Published private(set) var latestNetworkSample: NetworkSample?
    @Published private(set) var latestTemperatureSample: TemperatureSample?
    @Published private(set) var latestDiskSample: DiskSample?
    @Published private(set) var history = CPUHistory()
    @Published private(set) var ramHistory = RAMHistory()
    @Published private(set) var networkHistory = NetworkHistory()
    @Published private(set) var temperatureHistory = TemperatureHistory()
    @Published private(set) var diskHistory = DiskHistory()

    /// One bounded token event store + since-reset accumulator per provider (ADR-003).
    /// Ingested via `update(provider:with:)`; the popover/menu bar read the selected
    /// provider's store (or both, summed, for `combined`).
    @Published private(set) var tokenStores: [TokenProvider: TokenUsageStore]
    /// Token breakdown for the currently selected provider + scope + window, recomputed
    /// whenever events arrive or the provider/scope/window changes. For `combined` it is the
    /// sum of each provider's aggregate. Drives the menu bar and popover.
    @Published private(set) var tokenAggregate: TokenAggregate = .zero

    /// Interval the disk sampler ticks at, used to convert rolling-window rate
    /// sums into byte totals for the popover (see DiskWindowStats / ADR-002).
    let diskSampleInterval: TimeInterval = 1

    private enum TokenKeys {
        /// Legacy single reset key (pre-Codex). Migrated once into the Claude slot.
        static let legacyResetAt = "CPUState.tokenResetAt"
        static func resetAt(_ provider: TokenProvider) -> String {
            "CPUState.tokenResetAt.\(provider.rawValue)"
        }
    }

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

    var onVisibilityChange: ((MetricVisibilitySettings.Metric, Bool) -> Void)?
    var onDisplayChange: (() -> Void)?
    /// Called by the UI when the user taps Iniciar; AppDelegate wires the actual lock start.
    var onStartLock: ((TimeInterval) -> Void)?
    /// Called when the user requests a manual update check; AppDelegate forwards to the updater.
    var onCheckForUpdates: (() -> Void)?
    /// Called when the user asks to relaunch after granting Accessibility; AppDelegate owns the relaunch.
    var onRelaunch: (() -> Void)?
    /// Asks the UI to open the popover programmatically (for the one-time post-update
    /// nudge). AppDelegate wires this to `StatusItemController.openPopover()`.
    var onRequestOpenPopover: (() -> Void)?

    private let userDefaults: UserDefaults
    private let accessibilityAuthorization: AccessibilityAuthorizationProtocol
    private let accessibilityProbe: AccessibilityProbing
    private let currentAppVersion: String
    private var grantTracker: AccessibilityGrantTracker
    /// One-time auto-open nudge persistence (fires once per reset event).
    private var nudgeTracker: AccessibilityNudgeTracker
    /// Active only while `recoveryPhase == .awaitingGrant`; spawns a probe each tick.
    private var recoveryPollTimer: Timer?
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

    init(
        userDefaults: UserDefaults = .standard,
        accessibilityAuthorization: AccessibilityAuthorizationProtocol = SystemAccessibilityAuthorization(),
        accessibilityProbe: AccessibilityProbing? = nil,
        currentAppVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    ) {
        self.userDefaults = userDefaults
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
        display = MetricDisplaySettings.load(from: userDefaults)
        cleaningLockSettings = CleaningLockSettings.load(from: userDefaults)

        // Per-provider reset times. Migrate the legacy single key into the Claude slot once
        // (ADR-003), so an existing install's since-reset measurement carries over.
        let legacyResetAt = userDefaults.object(forKey: TokenKeys.legacyResetAt) as? Date
        let storedClaudeResetAt = userDefaults.object(forKey: TokenKeys.resetAt(.claude)) as? Date
        let claudeResetAt = storedClaudeResetAt ?? legacyResetAt ?? Date()
        let codexResetAt = (userDefaults.object(forKey: TokenKeys.resetAt(.codex)) as? Date) ?? Date()
        tokenStores = [
            .claude: TokenUsageStore(resetAt: claudeResetAt),
            .codex: TokenUsageStore(resetAt: codexResetAt)
        ]
        if storedClaudeResetAt == nil, let legacyResetAt {
            userDefaults.set(legacyResetAt, forKey: TokenKeys.resetAt(.claude))
            userDefaults.removeObject(forKey: TokenKeys.legacyResetAt)
        }

        evaluateAccessibility()
    }

    deinit {
        // No leaked poll timer if the state is torn down mid-recovery.
        recoveryPollTimer?.invalidate()
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

        if visibility.showTokens {
            let value = TokenFormatter.menuBarTitle(for: tokenAggregate, showLabel: false)
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

    var temperatureMenuBarTextStyle: CPUMenuBarTextStyle {
        TemperatureFormatter.menuBarTextStyle(for: latestTemperatureSample)
    }

    var diskMenuBarTextStyle: CPUMenuBarTextStyle {
        DiskFormatter.menuBarTextStyle(for: latestDiskSample)
    }

    var diskMenuBarMetric: MetricDisplaySettings.DiskMenuBarMetric {
        display.diskMenuBarMetric
    }

    /// Token volume has no danger threshold in the volume-only MVP — always `.normal`.
    var tokenMenuBarTextStyle: CPUMenuBarTextStyle {
        TokenFormatter.menuBarTextStyle(for: tokenAggregate)
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

    /// Whether the token meter has nothing meaningful to show (no logs / all-zero).
    var tokenIsEmpty: Bool {
        TokenFormatter.isEmpty(tokenAggregate)
    }

    /// Headline value for the popover token row: the humanized total, or the localized
    /// empty/zero state when there is no data.
    var tokenRowValue: String {
        tokenIsEmpty ? TokenFormatter.emptyState() : TokenFormatter.humanized(tokenAggregate.usageTotal)
    }

    /// Localized input/output/cache breakdown rows for the popover.
    var tokenBreakdown: [(label: String, value: String)] {
        TokenFormatter.breakdown(for: tokenAggregate)
    }

    /// Distinct friendly model names used within the current provider/scope/window, newest
    /// first (e.g. "GPT-5 Codex, Opus 4.8"). For `combined`, events from both providers are
    /// merged and ordered by recency. `nil` when there is no usage to attribute.
    var tokenActiveModels: String? {
        guard !tokenIsEmpty else { return nil }
        let now = Date()
        var events: [TokenUsageEvent] = []
        for provider in display.tokenProvider.providers {
            guard let store = tokenStores[provider] else { continue }
            events += TokenWindowStats.filteredEvents(
                store: store,
                scope: display.tokenScope,
                window: display.tokenMenuBarWindow,
                now: now
            )
        }
        events.sort { $0.timestamp > $1.timestamp }   // newest first across providers
        var seen = Set<String>()
        let names = events.compactMap { event -> String? in
            guard !seen.contains(event.model) else { return nil }
            seen.insert(event.model)
            return TokenFormatter.modelDisplayName(event.model)
        }
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    /// Sparkline values (0–100 normalized) of recent token volume for the selected
    /// provider/scope/window, mirroring `normalizedDiskTrend`. For `combined`, per-bucket
    /// totals are summed across providers before normalizing. Empty when there is no data.
    var tokenSparkline: [Double] {
        guard !tokenIsEmpty else { return [] }
        let now = Date()
        var summed: [Int] = []
        for provider in display.tokenProvider.providers {
            guard let store = tokenStores[provider] else { continue }
            let buckets = TokenWindowStats.sparklineBuckets(
                store: store,
                scope: display.tokenScope,
                window: display.tokenMenuBarWindow,
                now: now
            )
            if summed.isEmpty {
                summed = buckets
            } else {
                for index in buckets.indices where index < summed.count {
                    summed[index] += buckets[index]
                }
            }
        }
        guard let peak = summed.max(), peak > 0 else { return [] }
        return summed.map { Double($0) / Double(peak) * 100 }
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

        if visibility.showTokens {
            segments.append("\(Strings.tokens()) \(TokenFormatter.menuBarTitle(for: tokenAggregate, showLabel: false))")
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
    }

    func update(with sample: TemperatureSample) {
        latestTemperatureSample = sample
        temperatureHistory.append(sample)
    }

    func update(with sample: DiskSample) {
        latestDiskSample = sample
        diskHistory.append(sample)
    }

    /// Ingests a batch of parsed token events into the given provider's store and
    /// republishes the selected aggregate. Ingestion is independent of menu-bar visibility —
    /// like the other metrics, the popover keeps working when the segment is hidden.
    func update(provider: TokenProvider, with events: [TokenUsageEvent]) {
        guard !events.isEmpty else { return }
        for event in events {
            tokenStores[provider]?.append(event)
        }
        recomputeTokenAggregate()
    }

    /// Claude-provider convenience used by the existing Claude sampler path and tests.
    func update(with events: [TokenUsageEvent]) {
        update(provider: .claude, with: events)
    }

    func setTokenVisible(_ isVisible: Bool) {
        updateVisibility(metric: .tokens, isVisible: isVisible)
    }

    func setTokenScope(_ scope: TokenScope) {
        guard display.tokenScope != scope else { return }

        display.tokenScope = scope
        display.save(to: userDefaults)
        recomputeTokenAggregate()
        onDisplayChange?()
    }

    func setTokenMenuBarWindow(_ window: TokenWindow) {
        guard display.tokenMenuBarWindow != window else { return }

        display.tokenMenuBarWindow = window
        display.save(to: userDefaults)
        recomputeTokenAggregate()
        onDisplayChange?()
    }

    /// Switches the displayed provider (Claude / Codex / Combined), persists it, and
    /// republishes every token-derived surface from the already-ingested stores.
    func setTokenProvider(_ selection: TokenProviderSelection) {
        guard display.tokenProvider != selection else { return }

        display.tokenProvider = selection
        display.save(to: userDefaults)
        recomputeTokenAggregate()
        onDisplayChange?()
    }

    /// Starts a fresh since-reset measurement for the selected provider(s) — both when
    /// `combined` is selected (ADR-003). The rolling windows (today/1h/24h) are unaffected;
    /// only the since-reset view zeroes. Each provider's `resetAt` is persisted under its own
    /// key so it survives relaunch and rebuilds from the backfilled tail.
    func resetTokenCounter() {
        let now = Date()
        for provider in display.tokenProvider.providers {
            tokenStores[provider]?.reset(now: now)
            userDefaults.set(now, forKey: TokenKeys.resetAt(provider))
        }
        recomputeTokenAggregate()
    }

    /// The aggregate for the selected provider, or the sum of both providers' aggregates
    /// for `combined` (each computed independently with its own MRU — ADR-003).
    private func recomputeTokenAggregate() {
        let now = Date()
        tokenAggregate = display.tokenProvider.providers.reduce(.zero) { running, provider in
            guard let store = tokenStores[provider] else { return running }
            return running + TokenWindowStats.aggregate(
                store: store,
                scope: display.tokenScope,
                window: display.tokenMenuBarWindow,
                now: now
            )
        }
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

    func setMetricIdentifierStyle(_ identifierStyle: MetricDisplaySettings.IdentifierStyle) {
        guard display.identifierStyle != identifierStyle else { return }

        display.identifierStyle = identifierStyle
        display.save(to: userDefaults)
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
        }
    }
}
