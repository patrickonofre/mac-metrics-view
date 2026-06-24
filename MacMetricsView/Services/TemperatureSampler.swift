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

/// Injectable seam for the numeric poll. The real implementation drives a main run-loop
/// timer; tests inject a fake they can fire manually, avoiding real time.
@MainActor
protocol TemperaturePollScheduler {
    func schedule(interval: TimeInterval, tolerance: TimeInterval, _ action: @escaping @MainActor () -> Void)
    func cancel()
}

@MainActor
final class RunLoopTemperaturePollScheduler: TemperaturePollScheduler {
    private var timer: Timer?

    nonisolated init() {}

    func schedule(interval: TimeInterval, tolerance: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        timer = MainRunLoopTimer.repeating(every: interval, tolerance: tolerance, action)
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }
}

@MainActor
final class TemperatureSampler {
    private let reader: TemperatureReading
    private let notificationCenter: NotificationCenter
    private let deliveryQueue: OperationQueue?
    private(set) var pollInterval: TimeInterval
    private(set) var tolerance: TimeInterval = 0
    private let pollScheduler: TemperaturePollScheduler
    private let executor: SamplingExecutor
    private var observer: NSObjectProtocol?
    private(set) var isRunning = false

    weak var delegate: TemperatureSamplerDelegate?

    init(
        reader: TemperatureReading = IOKitTemperatureReader(),
        notificationCenter: NotificationCenter = .default,
        deliveryQueue: OperationQueue? = .main,
        pollInterval: TimeInterval = 3,
        pollScheduler: TemperaturePollScheduler = RunLoopTemperaturePollScheduler(),
        executor: SamplingExecutor = BackgroundSamplingExecutor()
    ) {
        self.reader = reader
        self.notificationCenter = notificationCenter
        self.deliveryQueue = deliveryQueue
        self.pollInterval = pollInterval
        self.pollScheduler = pollScheduler
        self.executor = executor
    }

    func start() {
        // Idempotent: AppDelegate may call start() both on launch and on a visibility
        // toggle, so a repeated start must not duplicate the observer or the timer.
        guard !isRunning else { return }
        isRunning = true

        // Thermal state is event-driven: macOS posts a notification when it changes.
        // The numeric Celsius reading does not, so it is polled on a modest timer that
        // runs only while the metric is visible (the sampler is stopped when hidden).
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
        pollScheduler.schedule(interval: pollInterval, tolerance: tolerance) { [weak self] in
            self?.collect()
        }
    }

    func start(interval: TimeInterval, tolerance: TimeInterval = 0) {
        self.pollInterval = interval
        self.tolerance = tolerance
        if isRunning {
            pollScheduler.cancel()
            pollScheduler.schedule(interval: pollInterval, tolerance: self.tolerance) { [weak self] in
                self?.collect()
            }
        } else {
            start()
        }
    }

    func stop() {
        if let observer {
            notificationCenter.removeObserver(observer)
        }
        observer = nil
        pollScheduler.cancel()
        isRunning = false
    }

    private func collect() {
        // The numeric SMC/IOKit read runs off the main thread (PERF-01); the sample is
        // delivered on the main actor. A nil read never notifies the delegate.
        executor.run({ [reader] in reader.readSample() }) { [weak self] sample in
            guard let self, let sample else { return }
            self.delegate?.temperatureSampler(self, didProduce: sample)
        }
    }
}

extension ProcessInfo.ThermalState {
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
