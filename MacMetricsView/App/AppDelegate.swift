import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, CPUSamplerDelegate, RAMSamplerDelegate, NetworkSamplerDelegate, TemperatureSamplerDelegate, DiskSamplerDelegate, BatterySamplerDelegate, AmbientLightSamplerDelegate, GPUSamplerDelegate {
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
    // Ambient-light sampler for the theme suggestion. Gated by the opt-in setting
    // (not menu-bar visibility): it runs whenever the feature is enabled. Internal so
    // wiring tests can drive the gated lifecycle.
    let ambientLightSampler = AmbientLightSampler()
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
        state.onPopoverOpenChange = { [weak self] isOpen in
            guard let self else { return }
            self.reevaluateSamplers()
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
        ambientLightSampler.delegate = self

        // The ambient sampler runs independently of menu-bar visibility / popover state:
        // it is gated purely by the opt-in flag, so re-evaluate it whenever the setting
        // changes (the Settings toggle flows through CPUState → this callback).
        state.onAmbientThemeSettingsChange = { [weak self] _ in
            self?.reevaluateAmbientSampler()
        }

        reevaluateSamplers()
        reevaluateAmbientSampler()
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
        ambientLightSampler.stop()
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
        statusItemController?.setNeedsTitleUpdate()
    }

    func ramSampler(_ sampler: RAMSampler, didProduce sample: RAMSample) {
        state.metrics.update(with: sample)
        statusItemController?.setNeedsTitleUpdate()
    }

    func networkSampler(_ sampler: NetworkSampler, didProduce sample: NetworkSample) {
        state.metrics.update(with: sample)
        statusItemController?.setNeedsTitleUpdate()
    }

    func temperatureSampler(_ sampler: TemperatureSampler, didProduce sample: TemperatureSample) {
        state.metrics.update(with: sample)
        statusItemController?.setNeedsTitleUpdate()
    }

    func diskSampler(_ sampler: DiskSampler, didProduce sample: DiskSample) {
        state.metrics.update(with: sample)
        statusItemController?.setNeedsTitleUpdate()
    }

    func gpuSampler(_ sampler: GPUSampler, didProduce sample: GPUSample) {
        state.metrics.update(with: sample)
        statusItemController?.setNeedsTitleUpdate()
    }

    func batterySampler(_ sampler: BatterySampler, didProduce sample: BatterySample) {
        state.metrics.update(with: sample)
        statusItemController?.setNeedsTitleUpdate()
    }

    func ambientLightSampler(_ sampler: AmbientLightSampler, didProduce sample: AmbientLightSample) {
        // Theme suggestion is a popover-only surface (no menu-bar segment), so no title
        // rebuild — CPUState republishes `themeSuggestion`/`latestAmbientSample` for the UI.
        state.update(with: sample)
    }

    func reevaluateSamplers() {
        let isPopoverOpen = state.isPopoverOpen
        let bgInterval = TimeInterval(state.metrics.display.updateRate)
        // Background ticks get 25% tolerance so the kernel coalesces all active samplers
        // into a single wakeup (ADR-002). The open popover keeps an exact 1s cadence
        // (tolerance 0) for fluid real-time graphs.
        let bgTolerance = bgInterval * 0.25

        if isPopoverOpen {
            // All samplers active at 1s for fluid real-time updates in popover
            cpuSampler.start(interval: 1.0, tolerance: 0)
            ramSampler.start(interval: 1.0, tolerance: 0)
            networkSampler.start(interval: 1.0, tolerance: 0)
            // Temperature keeps a slower 2s cadence even with the popover open (OPT-06 /
            // TD-013); the slow signal reads identically and saves the extra reads.
            temperatureSampler.start(interval: temperaturePopoverInterval, tolerance: 0)
            diskSampler.start(interval: 1.0, tolerance: 0)
            gpuSampler.start(interval: 1.0, tolerance: 0)

            // Battery keeps its event-driven + 30s safety poll cadence even with the popover
            // open (OPT-05): plug/unplug and charge ticks arrive as IOPS events in real time,
            // and openPopover() already does a one-shot read, so a 1s poll adds nothing.
            if batteryIsPresent {
                batterySampler.start(interval: batterySafetyPollInterval, tolerance: batterySafetyPollInterval * 0.25)
            } else {
                batterySampler.stop()
            }
        } else {
            // Popover is closed: only run samplers for visible menu bar metrics at the background rate.
            // Hidden metrics are completely stopped (suspended).

            if state.metrics.visibility.showCPU {
                cpuSampler.start(interval: bgInterval, tolerance: bgTolerance)
            } else {
                cpuSampler.stop()
            }

            if state.metrics.visibility.showRAM {
                ramSampler.start(interval: bgInterval, tolerance: bgTolerance)
            } else {
                ramSampler.stop()
            }

            if state.metrics.visibility.showNetwork {
                networkSampler.start(interval: bgInterval, tolerance: bgTolerance)
            } else {
                networkSampler.stop()
            }

            if state.metrics.visibility.showTemperature {
                // Fixed 3s background cadence, independent of updateRate (OPT-06 / TD-013).
                temperatureSampler.start(
                    interval: temperatureBackgroundInterval,
                    tolerance: temperatureBackgroundInterval * 0.25
                )
            } else {
                temperatureSampler.stop()
            }

            if state.metrics.visibility.showDisk {
                diskSampler.start(interval: bgInterval, tolerance: bgTolerance)
            } else {
                diskSampler.stop()
            }

            if state.metrics.visibility.showGPU {
                gpuSampler.start(interval: bgInterval, tolerance: bgTolerance)
            } else {
                gpuSampler.stop()
            }

            if state.metrics.visibility.showBattery && batteryIsPresent {
                batterySampler.start(interval: batterySafetyPollInterval, tolerance: batterySafetyPollInterval * 0.25)
            } else {
                batterySampler.stop()
            }
        }
    }

    /// Starts or stops the ambient sampler in step with the opt-in flag. Independent of
    /// `reevaluateSamplers` (visibility/popover-driven): ambient light changes slowly, so
    /// it polls on a fixed modest cadence with generous tolerance for wakeup coalescing.
    func reevaluateAmbientSampler() {
        if state.ambientThemeSettings.isEnabled {
            ambientLightSampler.start(interval: 10, tolerance: 2.5)
        } else {
            ambientLightSampler.stop()
        }
    }
}
