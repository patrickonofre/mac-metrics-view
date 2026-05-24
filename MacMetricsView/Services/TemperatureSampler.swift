import Foundation

protocol TemperatureReading {
    func readSample() -> TemperatureSample?
}

struct ProcessInfoTemperatureReader: TemperatureReading {
    func readSample() -> TemperatureSample? {
        TemperatureSample(celsius: nil, state: ProcessInfo.processInfo.thermalState.temperatureState)
    }
}

@MainActor
protocol TemperatureSamplerDelegate: AnyObject {
    func temperatureSampler(_ sampler: TemperatureSampler, didProduce sample: TemperatureSample)
}

final class TemperatureSampler {
    private let reader: TemperatureReading
    private let interval: TimeInterval
    private var timer: Timer?

    @MainActor weak var delegate: TemperatureSamplerDelegate?

    init(reader: TemperatureReading = ProcessInfoTemperatureReader(), interval: TimeInterval = 5) {
        self.reader = reader
        self.interval = interval
    }

    func start() {
        collect()

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
    }

    private func collect() {
        guard let sample = reader.readSample() else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.temperatureSampler(self, didProduce: sample)
        }
    }
}

private extension ProcessInfo.ThermalState {
    var temperatureState: TemperatureState {
        switch self {
        case .nominal:
            return .normal
        case .fair:
            return .warm
        case .serious:
            return .hot
        case .critical:
            return .critical
        @unknown default:
            return .unavailable
        }
    }
}
