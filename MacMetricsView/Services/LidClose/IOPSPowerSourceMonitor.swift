import Foundation

/// Power-source feed for the lid-close battery fail-safe (LIDC-14). `KeepAwakeModel`
/// observes snapshots only while the sub-mode is active; tests inject a fake.
@MainActor
protocol PowerSourceMonitoring: AnyObject {
    var onChange: ((PowerSourceSnapshot) -> Void)? { get set }
    func start()
    func stop()
}

/// `PowerSourceMonitoring` as a thin adapter over the existing `BatterySampler`
/// (design: reuse-first — the sampler already delivers event-driven IOPS changes
/// plus a modest poll; no new IOPS code). Owns a private sampler instance so the
/// fail-safe is independent of the battery metric's visibility gating.
@MainActor
final class IOPSPowerSourceMonitor: PowerSourceMonitoring, BatterySamplerDelegate {
    private let sampler: BatterySampler
    var onChange: ((PowerSourceSnapshot) -> Void)?

    /// `sampler` is injectable for tests; `nil` builds the default IOPS-backed one
    /// here (not as a default argument, which would evaluate outside the main actor).
    init(sampler: BatterySampler? = nil) {
        self.sampler = sampler ?? BatterySampler()
    }

    func start() {
        sampler.delegate = self
        sampler.start()
    }

    func stop() {
        sampler.stop()
        sampler.delegate = nil
    }

    /// Pure mapping from a battery reading to a fail-safe snapshot. `nil` when the
    /// charge percent is unreadable: the policy cannot be evaluated on a fabricated
    /// level, so such readings are dropped rather than guessed at.
    static func snapshot(from sample: BatterySample) -> PowerSourceSnapshot? {
        guard let level = sample.chargePercent else { return nil }
        return PowerSourceSnapshot(levelPercent: level, isOnBattery: sample.powerSource == .battery)
    }

    // MARK: - BatterySamplerDelegate

    func batterySampler(_ sampler: BatterySampler, didProduce sample: BatterySample) {
        guard let snapshot = Self.snapshot(from: sample) else { return }
        onChange?(snapshot)
    }
}
