import Foundation

enum DiskWindowStats {
    static func recentTotalBytes(
        in history: DiskHistory,
        interval: TimeInterval
    ) -> (read: UInt64, written: UInt64) {
        var totals = TrafficSessionTotals()
        for sample in history.samples {
            totals.add(inboundRate: sample.readBytesPerSecond, outboundRate: sample.writeBytesPerSecond,
                       elapsed: sample.measurementInterval ?? interval)
        }
        return (read: totals.inbound, written: totals.outbound)
    }

    static func recentPeakRates(in history: DiskHistory) -> (read: Double, write: Double) {
        let read = history.samples.map(\.readBytesPerSecond).max() ?? 0
        let write = history.samples.map(\.writeBytesPerSecond).max() ?? 0
        return (read: read, write: write)
    }
}
