import Foundation
import IOKit
import IOKit.ps

/// Reads the internal battery from public IOKit APIs: charge %, power source, charging
/// state, time remaining, and health condition from IOKit Power Sources (IOPS); cycle
/// count from the AppleSmartBattery IORegistry entry (ADR-001). Returns `nil` on Macs
/// with no internal battery (desktops). No entitlement, no network.
struct IOKitBatteryReader: BatteryReading {
    func readSample() -> BatterySample? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return nil
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }

            guard let type = description[kIOPSTypeKey] as? String,
                  type == kIOPSInternalBatteryType else { continue }

            return Self.makeSample(from: description, cycleCount: Self.readCycleCount())
        }

        return nil
    }

    /// Pure mapping from an IOPS power-source description (plus the separately-read cycle
    /// count) to a `BatterySample`. Exposed internally so the mapping is unit-testable
    /// without touching IOKit.
    static func makeSample(from description: [String: Any], cycleCount: Int?, now: Date = Date()) -> BatterySample {
        let charge: Int?
        let current = description[kIOPSCurrentCapacityKey] as? Int
        let maximum = description[kIOPSMaxCapacityKey] as? Int
        if let current, let maximum, maximum > 0 {
            charge = Int((Double(current) / Double(maximum) * 100).rounded())
        } else {
            charge = current
        }

        let stateString = description[kIOPSPowerSourceStateKey] as? String
        let powerSource: BatteryPowerSource = (stateString == kIOPSACPowerValue) ? .ac : .battery
        let isCharging = (description[kIOPSIsChargingKey] as? Bool) ?? false

        // IOPS reports time in minutes (negative sentinel while estimating). Pick the
        // relevant figure for the current direction; BatterySample normalizes the sentinel.
        let minutes = isCharging
            ? description[kIOPSTimeToFullChargeKey] as? Int
            : description[kIOPSTimeToEmptyKey] as? Int
        let timeRemaining: TimeInterval?
        if let minutes, minutes >= 0 {
            timeRemaining = TimeInterval(minutes * 60)
        } else {
            timeRemaining = nil
        }

        let condition: BatteryCondition
        if let conditionString = description[kIOPSBatteryHealthConditionKey] as? String {
            condition = conditionString.isEmpty ? .normal : .serviceRecommended
        } else {
            condition = .normal
        }

        return BatterySample(
            timestamp: now,
            chargePercent: charge,
            powerSource: powerSource,
            isCharging: isCharging,
            timeRemaining: timeRemaining,
            healthCondition: condition,
            cycleCount: cycleCount
        )
    }

    /// Cycle count from the AppleSmartBattery IORegistry entry, or `nil` when the key is
    /// absent (e.g. no battery). Releases the IOKit handle deterministically.
    static func readCycleCount() -> Int? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        guard let property = IORegistryEntryCreateCFProperty(
            service,
            "CycleCount" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else {
            return nil
        }

        return property as? Int
    }
}
