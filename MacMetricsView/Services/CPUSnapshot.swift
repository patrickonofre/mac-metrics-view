import Foundation

struct CPUSnapshot: Equatable {
    let user: UInt64
    let system: UInt64
    let idle: UInt64
    let nice: UInt64

    var total: UInt64 {
        user + system + idle + nice
    }
}

enum CPUSampleCalculator {
    static func sample(
        previous: CPUSnapshot,
        current: CPUSnapshot,
        timestamp: Date = Date()
    ) -> CPUSample? {
        guard current.user >= previous.user,
              current.system >= previous.system,
              current.idle >= previous.idle,
              current.nice >= previous.nice
        else {
            return nil
        }

        let userDelta = current.user - previous.user
        let systemDelta = current.system - previous.system
        let idleDelta = current.idle - previous.idle
        let niceDelta = current.nice - previous.nice
        let totalDelta = userDelta + systemDelta + idleDelta + niceDelta

        guard totalDelta > 0 else { return nil }

        let total = Double(totalDelta)
        let busy = Double(totalDelta - idleDelta)
        let totalUsage = busy / total * 100
        let userUsage = Double(userDelta + niceDelta) / total * 100
        let systemUsage = Double(systemDelta) / total * 100
        let idleUsage = Double(idleDelta) / total * 100

        guard totalUsage.isFinite,
              userUsage.isFinite,
              systemUsage.isFinite,
              idleUsage.isFinite
        else {
            return nil
        }

        return CPUSample(
            timestamp: timestamp,
            totalUsagePercent: totalUsage,
            userUsagePercent: userUsage,
            systemUsagePercent: systemUsage,
            idlePercent: idleUsage
        )
    }
}
