import Foundation

enum DiskWindowStats {
    static func recentTotalBytes(
        in history: DiskHistory,
        interval: TimeInterval
    ) -> (read: UInt64, written: UInt64) {
        guard interval > 0, interval.isFinite else { return (0, 0) }

        let readBytes = history.samples.reduce(0.0) { $0 + $1.readBytesPerSecond } * interval
        let writtenBytes = history.samples.reduce(0.0) { $0 + $1.writeBytesPerSecond } * interval

        return (
            read: UInt64(max(0, readBytes.rounded())),
            written: UInt64(max(0, writtenBytes.rounded()))
        )
    }

    static func recentPeakRates(in history: DiskHistory) -> (read: Double, write: Double) {
        let read = history.samples.map(\.readBytesPerSecond).max() ?? 0
        let write = history.samples.map(\.writeBytesPerSecond).max() ?? 0
        return (read: read, write: write)
    }
}
