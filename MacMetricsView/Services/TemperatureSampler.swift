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

@MainActor
final class TemperatureSampler {
    private let reader: TemperatureReading
    private let notificationCenter: NotificationCenter
    private let deliveryQueue: OperationQueue?
    private var observer: NSObjectProtocol?

    weak var delegate: TemperatureSamplerDelegate?

    init(
        reader: TemperatureReading = ProcessInfoTemperatureReader(),
        notificationCenter: NotificationCenter = .default,
        deliveryQueue: OperationQueue? = .main
    ) {
        self.reader = reader
        self.notificationCenter = notificationCenter
        self.deliveryQueue = deliveryQueue
    }

    func start() {
        // Thermal state is event-driven: macOS posts a notification when it changes,
        // so we sample once now and then only on change instead of polling a timer.
        collect()
        observer = notificationCenter.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: deliveryQueue
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.collect()
            }
        }
    }

    func stop() {
        if let observer {
            notificationCenter.removeObserver(observer)
        }
        observer = nil
    }

    private func collect() {
        guard let sample = reader.readSample() else { return }
        delegate?.temperatureSampler(self, didProduce: sample)
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
