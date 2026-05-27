import Foundation

struct RAMSample: Equatable {
    let timestamp: Date
    // "Memory Used" (App Memory + Wired + Compressed), kept for backward compatibility.
    let usedGB: Double
    let totalGB: Double
    let usedPercent: Double
    // App Memory (internal − purgeable): tracks app open/close, drives the menu bar by default.
    let appMemoryGB: Double
    let appMemoryPercent: Double
    // Memory pressure proxy ((wired + compressed) / total), see task-001 decision.
    let pressurePercent: Double

    init(
        timestamp: Date = Date(),
        usedGB: Double,
        totalGB: Double,
        usedPercent: Double,
        appMemoryGB: Double = 0,
        appMemoryPercent: Double = 0,
        pressurePercent: Double = 0
    ) {
        self.timestamp = timestamp
        self.usedGB = usedGB.isFinite ? max(0, usedGB) : 0
        self.totalGB = totalGB.isFinite ? max(0, totalGB) : 0
        self.usedPercent = usedPercent.clampedPercent
        self.appMemoryGB = appMemoryGB.isFinite ? max(0, appMemoryGB) : 0
        self.appMemoryPercent = appMemoryPercent.clampedPercent
        self.pressurePercent = pressurePercent.clampedPercent
    }
}
