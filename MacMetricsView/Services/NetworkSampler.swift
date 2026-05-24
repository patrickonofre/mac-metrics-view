import Foundation

protocol NetworkReading {
    func readSnapshot() -> NetworkCounterSnapshot?
}

@MainActor
protocol NetworkSamplerDelegate: AnyObject {
    func networkSampler(_ sampler: NetworkSampler, didProduce sample: NetworkSample)
}

final class NetworkSampler {
    private let reader: NetworkReading
    private let interval: TimeInterval
    private var previousSnapshot: NetworkCounterSnapshot?
    private var timer: Timer?

    @MainActor weak var delegate: NetworkSamplerDelegate?

    init(reader: NetworkReading = DarwinNetworkReader(), interval: TimeInterval = 1) {
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
              let sample = NetworkSampleCalculator.sample(previous: previousSnapshot, current: currentSnapshot)
        else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.networkSampler(self, didProduce: sample)
        }
    }
}
