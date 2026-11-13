import Foundation

struct NetworkSample: Equatable {
    let timestamp: Date
    let downloadBytesPerSecond: Double
    let uploadBytesPerSecond: Double
    /// Elapsed time between the counter snapshots that produced these rates.
    let measurementInterval: TimeInterval?

    init(
        timestamp: Date = Date(),
        downloadBytesPerSecond: Double,
        uploadBytesPerSecond: Double,
        measurementInterval: TimeInterval? = nil
    ) {
        self.timestamp = timestamp
        self.downloadBytesPerSecond = downloadBytesPerSecond.finiteNonNegativeRate
        self.uploadBytesPerSecond = uploadBytesPerSecond.finiteNonNegativeRate
        self.measurementInterval = measurementInterval
    }
}

extension Double {
    var finiteNonNegativeRate: Double {
        guard isFinite else { return 0 }
        return max(0, self)
    }
}
