import Foundation

struct CPUSample: Equatable {
    let timestamp: Date
    let totalUsagePercent: Double
    let userUsagePercent: Double?
    let systemUsagePercent: Double?
    let idlePercent: Double?

    init(
        timestamp: Date = Date(),
        totalUsagePercent: Double,
        userUsagePercent: Double? = nil,
        systemUsagePercent: Double? = nil,
        idlePercent: Double? = nil
    ) {
        self.timestamp = timestamp
        self.totalUsagePercent = totalUsagePercent.clampedPercent
        self.userUsagePercent = userUsagePercent?.clampedPercent
        self.systemUsagePercent = systemUsagePercent?.clampedPercent
        self.idlePercent = idlePercent?.clampedPercent
    }
}

extension Double {
    var clampedPercent: Double {
        guard isFinite else { return 0 }
        return min(100, max(0, self))
    }
}
