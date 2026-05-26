import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, CPUSamplerDelegate, RAMSamplerDelegate, NetworkSamplerDelegate, TemperatureSamplerDelegate {
    private let state = CPUState()
    private let launchAtLoginSettings = LaunchAtLoginSettings()
    private let cpuSampler = CPUSampler()
    private let ramSampler = RAMSampler()
    private let networkSampler = NetworkSampler()
    private let temperatureSampler = TemperatureSampler()
    private var statusItemController: StatusItemController?

    // Cleaning-lock
    private let lockService = CGEventTapInputLock()
    private var overlayController: LockOverlayController?

    // Auto-update (Sparkle in the Xcode build, no-op under SPM)
    private let updateService = makeAppUpdateService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        state.onVisibilityChange = { [weak self] metric, isVisible in
            self?.setSampler(for: metric, isVisible: isVisible)
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

        // Wire auto-update: apply the persisted preference, then forward UI actions.
        updateService.setAutomaticChecks(state.automaticUpdatesEnabled)
        state.onAutomaticUpdatesChange = { [weak self] enabled in
            self?.updateService.setAutomaticChecks(enabled)
        }
        state.onCheckForUpdates = { [weak self] in
            self?.updateService.checkForUpdates()
        }

        statusItemController = StatusItemController(
            state: state,
            launchAtLoginSettings: launchAtLoginSettings
        )
        cpuSampler.delegate = self
        ramSampler.delegate = self
        networkSampler.delegate = self
        temperatureSampler.delegate = self
        startVisibleSamplers()
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

    private func startVisibleSamplers() {
        if state.visibility.showCPU {
            cpuSampler.start()
        }

        if state.visibility.showRAM {
            ramSampler.start()
        }

        if state.visibility.showNetwork {
            networkSampler.start()
        }

        if state.visibility.showTemperature {
            temperatureSampler.start()
        }
    }

    private func setSampler(for metric: MetricVisibilitySettings.Metric, isVisible: Bool) {
        switch metric {
        case .cpu:
            isVisible ? cpuSampler.start() : cpuSampler.stop()
        case .ram:
            isVisible ? ramSampler.start() : ramSampler.stop()
        case .network:
            isVisible ? networkSampler.start() : networkSampler.stop()
        case .temperature:
            isVisible ? temperatureSampler.start() : temperatureSampler.stop()
        }
    }
}
