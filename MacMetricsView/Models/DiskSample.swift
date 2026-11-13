import Foundation

struct DiskSample: Equatable {
    let timestamp: Date
    let readBytesPerSecond: Double
    let writeBytesPerSecond: Double
    /// Elapsed time between the counter snapshots that produced these rates.
    let measurementInterval: TimeInterval?

    init(
        timestamp: Date = Date(),
        readBytesPerSecond: Double,
        writeBytesPerSecond: Double,
        measurementInterval: TimeInterval? = nil
    ) {
        self.timestamp = timestamp
        self.readBytesPerSecond = readBytesPerSecond.finiteNonNegativeRate
        self.writeBytesPerSecond = writeBytesPerSecond.finiteNonNegativeRate
        self.measurementInterval = measurementInterval
    }

    var totalBytesPerSecond: Double {
        readBytesPerSecond + writeBytesPerSecond
    }
}
