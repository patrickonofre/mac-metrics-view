import Foundation

struct DiskSample: Equatable {
    let timestamp: Date
    let readBytesPerSecond: Double
    let writeBytesPerSecond: Double

    init(
        timestamp: Date = Date(),
        readBytesPerSecond: Double,
        writeBytesPerSecond: Double
    ) {
        self.timestamp = timestamp
        self.readBytesPerSecond = readBytesPerSecond.finiteNonNegativeRate
        self.writeBytesPerSecond = writeBytesPerSecond.finiteNonNegativeRate
    }

    var totalBytesPerSecond: Double {
        readBytesPerSecond + writeBytesPerSecond
    }
}
