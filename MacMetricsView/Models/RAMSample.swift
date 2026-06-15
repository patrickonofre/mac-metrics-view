import Foundation

/// Kernel-reported system memory pressure, the honest "is memory a problem right now"
/// signal Activity Monitor surfaces as its green/yellow/red graph. Sourced from
/// `kern.memorystatus_vm_pressure_level`; `nil` when the level could not be read, in
/// which case callers fall back to percent-of-total heuristics.
enum MemoryPressureLevel: Equatable {
    case normal
    case warning
    case critical

    /// Maps the raw `kern.memorystatus_vm_pressure_level` sysctl value
    /// (1 = normal, 2 = warning, 4 = critical) to a level.
    init?(sysctlValue: Int32) {
        switch sysctlValue {
        case 1: self = .normal
        case 2: self = .warning
        case 4: self = .critical
        default: return nil
        }
    }
}

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
    // Activity-Monitor-style breakdown components, for the popover detail.
    let wiredGB: Double
    let compressedGB: Double
    let cachedFilesGB: Double
    let swapUsedGB: Double
    // Kernel-reported pressure level; nil when unavailable (callers fall back to percent).
    let pressureLevel: MemoryPressureLevel?

    init(
        timestamp: Date = Date(),
        usedGB: Double,
        totalGB: Double,
        usedPercent: Double,
        appMemoryGB: Double = 0,
        appMemoryPercent: Double = 0,
        pressurePercent: Double = 0,
        wiredGB: Double = 0,
        compressedGB: Double = 0,
        cachedFilesGB: Double = 0,
        swapUsedGB: Double = 0,
        pressureLevel: MemoryPressureLevel? = nil
    ) {
        self.timestamp = timestamp
        self.usedGB = usedGB.isFinite ? max(0, usedGB) : 0
        self.totalGB = totalGB.isFinite ? max(0, totalGB) : 0
        self.usedPercent = usedPercent.clampedPercent
        self.appMemoryGB = appMemoryGB.isFinite ? max(0, appMemoryGB) : 0
        self.appMemoryPercent = appMemoryPercent.clampedPercent
        self.pressurePercent = pressurePercent.clampedPercent
        self.wiredGB = wiredGB.isFinite ? max(0, wiredGB) : 0
        self.compressedGB = compressedGB.isFinite ? max(0, compressedGB) : 0
        self.cachedFilesGB = cachedFilesGB.isFinite ? max(0, cachedFilesGB) : 0
        self.swapUsedGB = swapUsedGB.isFinite ? max(0, swapUsedGB) : 0
        self.pressureLevel = pressureLevel
    }
}
