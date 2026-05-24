import Foundation

@MainActor
protocol CPUSamplerDelegate: AnyObject {
    func cpuSampler(_ sampler: CPUSampler, didProduce sample: CPUSample)
}

final class CPUSampler {
    private let reader: CPUReading
    private let interval: TimeInterval
    private var previousSnapshot: CPUSnapshot?
    private var timer: Timer?

    @MainActor weak var delegate: CPUSamplerDelegate?

    init(reader: CPUReading = MachCPUReader(), interval: TimeInterval = 1) {
        self.reader = reader
        self.interval = interval
    }

    func start() {
        previousSnapshot = reader.readSnapshot()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.timer?.invalidate()
            self.timer = Timer.scheduledTimer(withTimeInterval: self.interval, repeats: true) { [weak self] _ in
                self?.collect()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        previousSnapshot = nil
    }

    private func collect() {
        guard let currentSnapshot = reader.readSnapshot() else { return }
        defer { previousSnapshot = currentSnapshot }

        guard let previousSnapshot,
              let sample = CPUSampleCalculator.sample(previous: previousSnapshot, current: currentSnapshot)
        else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.cpuSampler(self, didProduce: sample)
        }
    }
}
