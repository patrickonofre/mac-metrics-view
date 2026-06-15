import Foundation
import IOKit.ps

/// Read seam for battery data. The concrete implementation wraps IOKit; tests inject a
/// fake. Returns `nil` when no battery is present (desktop Macs).
protocol BatteryReading {
    func readSample() -> BatterySample?
}

@MainActor
protocol BatterySamplerDelegate: AnyObject {
    func batterySampler(_ sampler: BatterySampler, didProduce sample: BatterySample)
}

/// Injectable seam for the poll fallback. The real implementation drives a main run-loop
/// timer; tests inject a fake they can fire manually, avoiding real time (mirrors
/// `TemperaturePollScheduler`).
@MainActor
protocol BatteryPollScheduler {
    func schedule(interval: TimeInterval, tolerance: TimeInterval, _ action: @escaping @MainActor () -> Void)
    func cancel()
}

@MainActor
final class RunLoopBatteryPollScheduler: BatteryPollScheduler {
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

/// Battery sampler mirroring `TemperatureSampler`: idempotent `start()`/`stop()`, a
/// delegate that emits each reading, driven by an event-driven IOPS change source plus a
/// modest poll for time-remaining drift. Started only while the metric is visible and a
/// battery is present (ADR-003); `AppDelegate` owns the gating.
@MainActor
final class BatterySampler {
    private let reader: BatteryReading
    private(set) var pollInterval: TimeInterval
    private(set) var tolerance: TimeInterval = 0
    private let pollScheduler: BatteryPollScheduler
    private var runLoopSource: CFRunLoopSource?
    private(set) var isRunning = false

    weak var delegate: BatterySamplerDelegate?

    init(
        reader: BatteryReading = IOKitBatteryReader(),
        pollInterval: TimeInterval = 30,
        pollScheduler: BatteryPollScheduler = RunLoopBatteryPollScheduler()
    ) {
        self.reader = reader
        self.pollInterval = pollInterval
        self.pollScheduler = pollScheduler
    }

    /// Whether an internal battery is present, via a non-empty IOPS internal-battery
    /// source. Used by the lifecycle gate so desktop Macs never start the sampler.
    static func batteryIsPresent() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return false
        }

        for source in sources {
            if let description = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any],
                let type = description[kIOPSTypeKey] as? String,
                type == kIOPSInternalBatteryType {
                return true
            }
        }

        return false
    }

    func start() {
        // Idempotent: AppDelegate may call start() on launch and on a visibility toggle,
        // so a repeated start must not duplicate the run-loop source or the timer.
        guard !isRunning else { return }
        isRunning = true

        collect()

        // Power-source changes (plug/unplug, charge ticks) are event-driven via IOPS.
        // The numeric time-remaining estimate drifts between events, so it is also polled
        // on a modest timer that runs only while the sampler is active.
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ rawContext in
            guard let rawContext else { return }
            let sampler = Unmanaged<BatterySampler>.fromOpaque(rawContext).takeUnretainedValue()
            MainActor.assumeIsolated {
                sampler.collect()
            }
        }, context)?.takeRetainedValue() {
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
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
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        pollScheduler.cancel()
        isRunning = false
    }

    private func collect() {
        guard let sample = reader.readSample() else { return }
        delegate?.batterySampler(self, didProduce: sample)
    }
}
