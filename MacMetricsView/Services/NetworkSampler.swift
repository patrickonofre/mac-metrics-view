import Foundation

protocol NetworkReading {
    func readSnapshot() -> NetworkCounterSnapshot?
}

@MainActor
protocol NetworkSamplerDelegate: AnyObject {
    func networkSampler(_ sampler: NetworkSampler, didProduce sample: NetworkSample)
}

@MainActor
final class NetworkSampler {
    private let reader: NetworkReading
    private(set) var interval: TimeInterval
    private var previousSnapshot: NetworkCounterSnapshot?
    private var timer: Timer?

    weak var delegate: NetworkSamplerDelegate?

    var isRunning: Bool { timer != nil }

    init(reader: NetworkReading = DarwinNetworkReader(), interval: TimeInterval = 1) {
        self.reader = reader
        self.interval = interval
    }

    func start() {
        timer?.invalidate()
        previousSnapshot = reader.readSnapshot()
        timer = MainRunLoopTimer.repeating(every: interval) { [weak self] in self?.collect() }
    }

    func start(interval: TimeInterval) {
        self.interval = interval
        start()
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
              let sample = NetworkSampleCalculator.sample(previous: previousSnapshot, current: currentSnapshot)
        else {
            return
        }

        delegate?.networkSampler(self, didProduce: sample)
    }
}
