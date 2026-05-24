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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        state.onVisibilityChange = { [weak self] metric, isVisible in
            self?.setSampler(for: metric, isVisible: isVisible)
            self?.statusItemController?.setNeedsTitleUpdate()
        }
        state.onDisplayChange = { [weak self] in
            self?.statusItemController?.setNeedsTitleUpdate()
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
        cpuSampler.stop()
        ramSampler.stop()
        networkSampler.stop()
        temperatureSampler.stop()
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
