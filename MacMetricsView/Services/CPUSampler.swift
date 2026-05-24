import Foundation

@MainActor
protocol CPUSamplerDelegate: AnyObject {
    func cpuSampler(_ sampler: CPUSampler, didProduce sample: CPUSample)
}

@MainActor
final class CPUSampler {
    private let reader: CPUReading
    private let interval: TimeInterval
    private var previousSnapshot: CPUSnapshot?
    private var timer: Timer?

    weak var delegate: CPUSamplerDelegate?

    init(reader: CPUReading = MachCPUReader(), interval: TimeInterval = 1) {
        self.reader = reader
        self.interval = interval
    }

    func start() {
        previousSnapshot = reader.readSnapshot()
        timer = MainRunLoopTimer.repeating(every: interval) { [weak self] in self?.collect() }
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

        delegate?.cpuSampler(self, didProduce: sample)
    }
}
