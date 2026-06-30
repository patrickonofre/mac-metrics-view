import Foundation

/// The System metrics pillar (TD-012): CPU/RAM/network/disk/temperature/battery/GPU
/// samples, history, menu-bar visibility/display settings, and process sampling.
/// Extracted from `CPUState` (spec `spec-cpustate-pillar-decouple`, task-005) — the
/// last and largest pillar, leaving `CPUState` as a pure coordinator (children +
/// menu-bar title composition + cross-cutting state). Like `token`, `StatusItemController`
/// never needs to observe this model reactively: `AppDelegate`'s sampler delegates push
/// `setNeedsTitleUpdate()` explicitly after every `update(with:)` call. SwiftUI consumers
/// (`MetricsTab`, `SettingsTab`) observe `metrics` directly as their own `@ObservedObject`.
@MainActor
final class SystemMetricsModel: ObservableObject {
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

    /// Interval the disk sampler ticks at, used to convert rolling-window rate
    /// sums into byte totals for the popover (see DiskWindowStats / ADR-002).
    let diskSampleInterval: TimeInterval = 1

    var onVisibilityChange: ((MetricVisibilitySettings.Metric, Bool) -> Void)?
    var onDisplayChange: (() -> Void)?

    private let userDefaults: UserDefaults
    private let processReader: ProcessReading
    /// Runs the all-PID process enumeration off the main thread (PERF-01). The reader's mutable
    /// state (its PID→name cache) is touched only inside the executor; `previousProcessSnapshot`
    /// stays main-confined and is read/written only in the main-actor delivery closure.
    private let samplingExecutor: SamplingExecutor
    private var previousProcessSnapshot: ProcessCPUSnapshot?
    private var processSamplingTimer: Timer?
    /// One-shot battery reader used to refresh the popover row on open, so the popover
    /// shows live battery data like every other metric even while the menu-bar segment
    /// is hidden and the continuous sampler is gated off (ADR-003). Returns nil on Macs
    /// with no battery, so `latestBatterySample` stays nil → "no battery" row.
    private let batteryReader: BatteryReading

    init(
        userDefaults: UserDefaults,
        processReader: ProcessReading,
        samplingExecutor: SamplingExecutor,
        batteryReader: BatteryReading
    ) {
        self.userDefaults = userDefaults
        self.processReader = processReader
        self.samplingExecutor = samplingExecutor
        self.batteryReader = batteryReader
        visibility = MetricVisibilitySettings.load(from: userDefaults)
        let loadedDisplay = MetricDisplaySettings.resolved(from: userDefaults)
        display = loadedDisplay
        updateRate = loadedDisplay.updateRate
    }

    deinit {
        // No leaked timers if the model is torn down mid-popover-open.
        processSamplingTimer?.invalidate()
    }

    // MARK: - Presentation

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

    var hasVisibleMetric: Bool {
        visibility.hasVisibleMetric
    }

    // MARK: - Sample ingest

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

    // MARK: - Visibility + display settings

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

    /// Forwards the token visibility toggle: `MetricVisibilitySettings` covers all
    /// metric segments including tokens, even though token data itself lives in
    /// `TokenUsageModel`.
    func setTokenVisible(_ isVisible: Bool) {
        updateVisibility(metric: .tokens, isVisible: isVisible)
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

    /// Persists a token-related display setting (scope/window/provider/budgets) saved by
    /// the coordinator and republishes `display` so SwiftUI pickers reflect it. The
    /// coordinator owns pushing the change into `TokenUsageModel` — this model only
    /// stores the persisted slice, since token *data* lives in `TokenUsageModel`.
    func replaceDisplay(_ newDisplay: MetricDisplaySettings) {
        display = newDisplay
        display.save(to: userDefaults)
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
}
