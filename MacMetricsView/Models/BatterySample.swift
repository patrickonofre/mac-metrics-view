import Foundation

/// Whether the Mac is drawing from the battery or from AC power.
enum BatteryPowerSource: Equatable {
    case battery
    case ac
}

/// The macOS battery health condition, as reported by IOKit Power Sources
/// (`kIOPSBatteryHealthConditionKey`). Mirrors what System Settings shows: a
/// healthy battery has no condition key (`.normal`); a flagged one reads
/// `.serviceRecommended` (ADR-001 — condition string, not a computed percentage).
enum BatteryCondition: Equatable {
    case normal
    case serviceRecommended
    case unknown

    func localizedName(in language: AppLanguage = .current) -> String {
        let text: LocalizedText
        switch self {
        case .normal:
            text = Strings.batteryHealthNormal
        case .serviceRecommended:
            text = Strings.batteryServiceRecommended
        case .unknown:
            text = Strings.unavailable
        }
        return text(language)
    }
}

/// One in-memory battery reading. Pure value type (Foundation only) so it is
/// unit-testable without IOKit. Out-of-range charge, the macOS time sentinel
/// (negative while still estimating), and a missing cycle count all normalize to
/// `nil` so no impossible value reaches the UI.
struct BatterySample: Equatable {
    static let plausibleChargeRange = 0...100

    let timestamp: Date
    let chargePercent: Int?
    let powerSource: BatteryPowerSource
    let isCharging: Bool
    let timeRemaining: TimeInterval?
    let healthCondition: BatteryCondition
    let cycleCount: Int?

    init(
        timestamp: Date = Date(),
        chargePercent: Int?,
        powerSource: BatteryPowerSource,
        isCharging: Bool,
        timeRemaining: TimeInterval?,
        healthCondition: BatteryCondition,
        cycleCount: Int?
    ) {
        self.timestamp = timestamp

        if let chargePercent, Self.plausibleChargeRange.contains(chargePercent) {
            self.chargePercent = chargePercent
        } else {
            self.chargePercent = nil
        }

        self.powerSource = powerSource
        self.isCharging = isCharging

        // macOS reports a negative sentinel while it is still estimating time-to-empty /
        // time-to-full; treat anything non-finite or negative as "calculating".
        if let timeRemaining, timeRemaining.isFinite, timeRemaining >= 0 {
            self.timeRemaining = timeRemaining
        } else {
            self.timeRemaining = nil
        }

        self.healthCondition = healthCondition

        if let cycleCount, cycleCount >= 0 {
            self.cycleCount = cycleCount
        } else {
            self.cycleCount = nil
        }
    }
}
