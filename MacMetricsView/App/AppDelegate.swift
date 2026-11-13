import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, CPUSamplerDelegate, RAMSamplerDelegate, NetworkSamplerDelegate, TemperatureSamplerDelegate, DiskSamplerDelegate, BatterySamplerDelegate, GPUSamplerDelegate {
    // Lazy so the first-run metric preset can seed UserDefaults *before* CPUState loads
    // its visibility (see applyFirstRunMetricPresetIfNeeded()). Internal (not private) so
    // wiring tests can observe the published state after a delegate callback.
    lazy var state = CPUState()
    private let launchAtLoginSettings = LaunchAtLoginSettings()
    let cpuSampler = CPUSampler()
    let ramSampler = RAMSampler()
    let networkSampler = NetworkSampler()
    let temperatureSampler = TemperatureSampler()
    let diskSampler = DiskSampler()
    let gpuSampler = GPUSampler()
    // Internal so wiring tests can drive the gated lifecycle and assert routing.
    let batterySampler = BatterySampler()
    private var statusItemController: StatusItemController?

    /// Battery presence is fixed by hardware for the process lifetime, so the full IOPS
    /// snapshot `batteryIsPresent()` runs is resolved once instead of on every
    /// `reevaluateSamplers` (OPT-15).
    private lazy var batteryIsPresent: Bool = BatterySampler.batteryIsPresent()
    /// The battery sampler is event-driven (IOPS plug/charge notifications); the timer only
    /// refreshes the slow-drifting time-remaining estimate, so a modest safety poll is enough
    /// in every state (OPT-05). Restores the sampler's own 30s design default, which
    /// `reevaluateSamplers` had been overriding with the metric update rate.
    private let batterySafetyPollInterval: TimeInterval = 30

    /// Temperature runs on a fixed cadence independent of the metric update rate (OPT-06 /
    /// TD-013): die temperature changes slowly and the menu bar shows whole degrees, so a
    /// slower read is visually identical while removing the largest remaining background cost.
    private let temperatureBackgroundInterval: TimeInterval = 3
    private let temperaturePopoverInterval: TimeInterval = 2

    // Cleaning-lock
    private let lockService = CGEventTapInputLock()
    private var overlayController: LockOverlayController?

    // Auto-update (Sparkle in the Xcode build, no-op under SPM)
    private let updateService = makeAppUpdateService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Capture mode (MMV_CAPTURE=1, dev-only): run as a regular, focusable app so the
        // popover renders as a normal window for screenshots. Accessory otherwise.
        let captureMode = ProcessInfo.processInfo.environment["MMV_CAPTURE"] == "1"
        NSApplication.shared.setActivationPolicy(captureMode ? .regular : .accessory)

        // Must run before the first `state` access, which constructs CPUState and loads
        // visibility from UserDefaults.
        applyFirstRunMetricPresetIfNeeded()

        state.onVisibilityChange = { [weak self] metric, isVisible in
            guard let self else { return }
            self.reevaluateSamplers()
            self.statusItemController?.setNeedsTitleUpdate()
        }
        state.onDisplayChange = { [weak self] in
            guard let self else { return }
            self.reevaluateSamplers()
            self.statusItemController?.setNeedsTitleUpdate()
        }
        state.onPopoverOpenChange = { [weak self] _ in
            self?.reevaluateSamplers()
        }
        state.onMetricsTabChange = { [weak self] in
            self?.reevaluateSamplers()
        }

        // Wire cleaning lock: state fires onStartLock → we start the service + overlay.
        state.onStartLock = { [weak self] duration in
            self?.beginLockSession(duration: duration)
        }
        lockService.onTick = { [weak self] remaining in
            self?.state.updateLockState(phase: .locked, remaining: remaining)
        }
        lockService.onEnd = { [weak self] reason in
            self?.endLockSession(reason: reason)
        }

        // Wire update controls: forward the manual check and feed the passive
        // version probe into the published state, then probe once at launch.
        state.onCheckForUpdates = { [weak self] in
            self?.updateService.checkForUpdates()
        }
        state.onRelaunch = { [weak self] in
            self?.relaunch()
        }
        updateService.onAvailableVersionChange = { [weak self] version in
            self?.state.setAvailableUpdateVersion(version)
        }
        updateService.probeForUpdateInformation()

        statusItemController = StatusItemController(
            state: state,
            launchAtLoginSettings: launchAtLoginSettings
        )

        // Proactive recovery nudge: let CPUState open the popover programmatically
        // for the one-time post-update auto-open. Wired after the status item exists
        // so there is a host to open into; reuses the existing relaunch handshake
        // (state.onRelaunch → relaunch()) to apply a detected grant.
        state.onRequestOpenPopover = { [weak self] in
            self?.statusItemController?.openPopover()
        }
        // Defer to the next run-loop turn so the status-bar button is laid out and
        // has a window before an auto-open tries to anchor a popover to it.
        DispatchQueue.main.async { [weak self] in
            self?.state.evaluateAccessibilityLaunchNudge()
        }

        // Capture mode: bring the app forward and open the popover so a screenshot tool can
        // grab it. Deferred so the status-bar button is laid out and has a window first.
        if captureMode {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                NSApplication.shared.activate(ignoringOtherApps: true)
                self?.statusItemController?.openPopover()
            }
        }

        cpuSampler.delegate = self
        ramSampler.delegate = self
        networkSampler.delegate = self
        temperatureSampler.delegate = self
        diskSampler.delegate = self
        gpuSampler.delegate = self
        batterySampler.delegate = self
        reevaluateSamplers()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Failsafe: always release input before the process exits.
        if lockService.phase == .locked {
            lockService.stop(reason: .terminated)
        }
        // Failsafe (LIDC-11): a normal quit must clear the system sleep-disabled
        // flag before the process exits.
        deactivateLidCloseBeforeExit()
        cpuSampler.stop()
        ramSampler.stop()
        networkSampler.stop()
        temperatureSampler.stop()
        diskSampler.stop()
        gpuSampler.stop()
        batterySampler.stop()
    }

    /// Handle to the quit-failsafe deactivation (LIDC-11). Internal so wiring tests
    /// can await it deterministically instead of racing the fire-and-forget task.
    private(set) var lidCloseTerminationTask: Task<Void, Never>?

    /// How long `applicationWillTerminate` may pump the run loop waiting for the
    /// lid-close deactivation to settle. Internal so wiring tests can zero it: under
    /// XCTest the pump cannot drain the main actor (the test's own main-actor frame
    /// holds it), so tests await `lidCloseTerminationTask` instead.
    var lidCloseTerminationPumpTimeout: TimeInterval = 2

    /// Quit failsafe for the lid-close sub-mode (feature `lid-close-keep-awake`,
    /// LIDC-11): enqueues the deactivation through the model's serialized transition
    /// queue, then pumps the run loop briefly until the sub-mode reads `.off` so the
    /// helper call actually happens before exit. Bounded by a deadline so a hung
    /// helper can never block quit — the daemon's connection-loss revert (LIDC-12)
    /// and pmset's reboot-clears semantics are the backstops.
    private func deactivateLidCloseBeforeExit() {
        let keepAwake = state.keepAwake
        guard keepAwake.lidClose != .off else { return }
        lidCloseTerminationTask = Task { @MainActor in
            await keepAwake.setLidCloseActive(false)
        }
        let deadline = Date().addingTimeInterval(lidCloseTerminationPumpTimeout)
        while keepAwake.lidClose != .off && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }

    /// Seeds the first-run metric preset once, on a genuinely fresh install. The grant
    /// tracker records a version on every launch, so an empty tracker means the app has
    /// never run here. Existing installs and any user-chosen visibility are left untouched
    /// (see `MetricVisibilitySettings.resolved(from:isFreshInstall:)`).
    private func applyFirstRunMetricPresetIfNeeded() {
        let tracker = AccessibilityGrantTracker.load()
        let isFreshInstall = tracker.lastSeenVersion == nil && tracker.lastGrantedVersion == nil
        _ = MetricVisibilitySettings.resolved(isFreshInstall: isFreshInstall)
    }

    // MARK: - Relaunch

    /// Restarts the app so a freshly granted Accessibility permission is picked
    /// up — `AXIsProcessTrusted()` is cached for the process lifetime, so the
    /// running build cannot observe the grant until it relaunches.
    ///
    /// Spawns a detached shell that waits for *this* process to exit before
    /// reopening the bundle. Reopening while still running could leave two menu
    /// bar items, so we wait on the PID first. Path is single-quoted (its own
    /// bundle path, not user input) to stay safe if it contains spaces.
    private func relaunch() {
        let bundleURL = Bundle.main.bundleURL
        let pid = ProcessInfo.processInfo.processIdentifier
        let quotedPath = "'" + bundleURL.path.replacingOccurrences(of: "'", with: "'\\''") + "'"

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = [
            "-c",
            "while /bin/kill -0 \(pid) >/dev/null 2>&1; do /bin/sleep 0.1; done; /usr/bin/open \(quotedPath)"
        ]

        do {
            try task.run()
        } catch {
            // Fallback: ask the workspace to start a fresh instance directly.
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration)
        }

        NSApp.terminate(nil)
    }

    // MARK: - Lock session

    private func beginLockSession(duration: TimeInterval) {
        state.updateLockState(phase: .locked, remaining: duration)
        lockService.start(duration: duration)
        let controller = LockOverlayController()
        overlayController = controller
        controller.show(lock: state.lock)
    }

    private func endLockSession(reason: LockEndReason) {
        overlayController?.hide()
        overlayController = nil
        state.updateLockState(phase: .idle, remaining: 0)
    }

    func cpuSampler(_ sampler: CPUSampler, didProduce sample: CPUSample) {
        state.metrics.update(with: sample)
        scheduleTitleUpdate(for: .cpu)
    }

    func ramSampler(_ sampler: RAMSampler, didProduce sample: RAMSample) {
        state.metrics.update(with: sample)
        scheduleTitleUpdate(for: .ram)
    }

    func networkSampler(_ sampler: NetworkSampler, didProduce sample: NetworkSample) {
        state.metrics.update(with: sample)
        scheduleTitleUpdate(for: .network)
    }

    func temperatureSampler(_ sampler: TemperatureSampler, didProduce sample: TemperatureSample) {
        state.metrics.update(with: sample)
        scheduleTitleUpdate(for: .temperature)
    }

    func diskSampler(_ sampler: DiskSampler, didProduce sample: DiskSample) {
        state.metrics.update(with: sample)
        scheduleTitleUpdate(for: .disk)
    }

    func gpuSampler(_ sampler: GPUSampler, didProduce sample: GPUSample) {
        state.metrics.update(with: sample)
        scheduleTitleUpdate(for: .gpu)
    }

    func batterySampler(_ sampler: BatterySampler, didProduce sample: BatterySample) {
        state.metrics.update(with: sample)
        scheduleTitleUpdate(for: .battery)
    }

    private func scheduleTitleUpdate(for metric: MetricVisibilitySettings.Metric) {
        guard state.metrics.isVisibleInMenuBar(metric) else { return }
        statusItemController?.setNeedsTitleUpdate()
    }

    func reevaluateSamplers() {
        let showingMetrics = state.isMetricsTabVisible
        let visibility = state.metrics.visibility
        let interval = showingMetrics ? 1 : TimeInterval(state.metrics.updateRate)
        // Keep exact ticks while graphs are visible. Elsewhere the kernel can group wakeups.
        let tolerance = showingMetrics ? 0 : interval * 0.25

        if showingMetrics || visibility.showCPU {
            cpuSampler.start(interval: interval, tolerance: tolerance)
        } else {
            cpuSampler.stop()
        }
        if showingMetrics || visibility.showRAM {
            ramSampler.start(interval: interval, tolerance: tolerance)
        } else {
            ramSampler.stop()
        }
        if showingMetrics || visibility.showNetwork {
            networkSampler.start(interval: interval, tolerance: tolerance)
        } else {
            networkSampler.stop()
        }
        // Temperature follows TD-013 and stays independent of the menu bar update rate.
        if showingMetrics || visibility.showTemperature {
            let temperatureInterval = showingMetrics ? temperaturePopoverInterval : temperatureBackgroundInterval
            temperatureSampler.start(interval: temperatureInterval, tolerance: showingMetrics ? 0 : temperatureInterval * 0.25)
        } else {
            temperatureSampler.stop()
        }
        if showingMetrics || visibility.showDisk {
            diskSampler.start(interval: interval, tolerance: tolerance)
        } else {
            diskSampler.stop()
        }
        if showingMetrics || visibility.showGPU {
            gpuSampler.start(interval: interval, tolerance: tolerance)
        } else {
            gpuSampler.stop()
        }
        // IOPS events and the 30s safety poll cover the battery in either mode (OPT-05).
        if (showingMetrics || visibility.showBattery) && batteryIsPresent {
            batterySampler.start(interval: batterySafetyPollInterval, tolerance: batterySafetyPollInterval * 0.25)
        } else {
            batterySampler.stop()
        }
    }
}
