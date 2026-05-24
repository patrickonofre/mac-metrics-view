import Foundation

struct RAMSample: Equatable {
    let timestamp: Date
    let usedGB: Double
    let totalGB: Double
    let usedPercent: Double

    init(
        timestamp: Date = Date(),
        usedGB: Double,
        totalGB: Double,
        usedPercent: Double
    ) {
        self.timestamp = timestamp
        self.usedGB = usedGB.isFinite ? max(0, usedGB) : 0
        self.totalGB = totalGB.isFinite ? max(0, totalGB) : 0
        self.usedPercent = usedPercent.clampedPercent
    }
}
