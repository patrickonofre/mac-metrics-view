import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, CPUSamplerDelegate, RAMSamplerDelegate, NetworkSamplerDelegate, TemperatureSamplerDelegate, DiskSamplerDelegate, TokenUsageSamplerDelegate {
    // Lazy so the first-run metric preset can seed UserDefaults *before* CPUState loads
    // its visibility (see applyFirstRunMetricPresetIfNeeded()). Internal (not private) so
    // wiring tests can observe the published state after a delegate callback.
    lazy var state = CPUState()
    private let launchAtLoginSettings = LaunchAtLoginSettings()
    private let cpuSampler = CPUSampler()
    private let ramSampler = RAMSampler()
    private let networkSampler = NetworkSampler()
    private let temperatureSampler = TemperatureSampler()
    private let diskSampler = DiskSampler()
    // Internal (not private) so wiring tests can drive the delegate with the exact sampler
    // instances and assert provider-tagged routing, mirroring `state`.
    let tokenSampler = TokenUsageSampler()
    let codexTokenSampler = TokenUsageSampler(reader: CodexLogReader())
    private var statusItemController: StatusItemController?

    // Cleaning-lock
    private let lockService = CGEventTapInputLock()
    private var overlayController: LockOverlayController?

    // Auto-update (Sparkle in the Xcode build, no-op under SPM)
    private let updateService = makeAppUpdateService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        // Must run before the first `state` access, which constructs CPUState and loads
        // visibility from UserDefaults.
        applyFirstRunMetricPresetIfNeeded()

        state.onVisibilityChange = { [weak self] _, _ in
            // Visibility only curates the menu bar; samplers always run so the popover
            // keeps showing every metric. Just rebuild the title.
            self?.statusItemController?.setNeedsTitleUpdate()
        }
        state.onDisplayChange = { [weak self] in
            self?.statusItemController?.setNeedsTitleUpdate()
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

        cpuSampler.delegate = self
        ramSampler.delegate = self
        networkSampler.delegate = self
        temperatureSampler.delegate = self
        diskSampler.delegate = self
        tokenSampler.delegate = self
        codexTokenSampler.delegate = self
        startAllSamplers()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Failsafe: always release input before the process exits.
        if lockService.phase == .locked {
            lockService.stop(reason: .terminated)
        }
        cpuSampler.stop()
        ramSampler.stop()
        networkSampler.stop()
        temperatureSampler.stop()
        diskSampler.stop()
        tokenSampler.stop()
        codexTokenSampler.stop()
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
        controller.show(state: state)
    }

    private func endLockSession(reason: LockEndReason) {
        overlayController?.hide()
        overlayController = nil
        state.updateLockState(phase: .idle, remaining: 0)
    }

    func cpuSampler(_ sampler: CPUSampler, didProduce sample: CPUSample) {
        state.update(with: sample)
        statusItemController?.setNeedsTitleUpdate()
    }

    func ramSampler(_ sampler: RAMSampler, didProduce sample: RAMSample) {
        state.update(with: sample)
        statusItemController?.setNeedsTitleUpdate()
    }

    func networkSampler(_ sampler: NetworkSampler, didProduce sample: NetworkSample) {
        state.update(with: sample)
        statusItemController?.setNeedsTitleUpdate()
    }

    func temperatureSampler(_ sampler: TemperatureSampler, didProduce sample: TemperatureSample) {
        state.update(with: sample)
        statusItemController?.setNeedsTitleUpdate()
    }

    func diskSampler(_ sampler: DiskSampler, didProduce sample: DiskSample) {
        state.update(with: sample)
        statusItemController?.setNeedsTitleUpdate()
    }

    func tokenUsageSampler(_ sampler: TokenUsageSampler, didProduce events: [TokenUsageEvent]) {
        // Route each sampler's batch to its provider store; default to Claude for any other
        // sampler instance (back-compat with the single-sampler call sites).
        let provider: TokenProvider = sampler === codexTokenSampler ? .codex : .claude
        state.update(provider: provider, with: events)
        statusItemController?.setNeedsTitleUpdate()
    }

    private func startAllSamplers() {
        // Every metric is sampled so the popover always shows live data; menu-bar
        // visibility is applied when the title is built, not at the sampler.
        cpuSampler.start()
        ramSampler.start()
        networkSampler.start()
        temperatureSampler.start()
        diskSampler.start()
        tokenSampler.start()
        codexTokenSampler.start()
    }
}
