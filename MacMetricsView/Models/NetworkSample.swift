import Foundation

struct NetworkSample: Equatable {
    let timestamp: Date
    let downloadBytesPerSecond: Double
    let uploadBytesPerSecond: Double

    init(
        timestamp: Date = Date(),
        downloadBytesPerSecond: Double,
        uploadBytesPerSecond: Double
    ) {
        self.timestamp = timestamp
        self.downloadBytesPerSecond = downloadBytesPerSecond.finiteNonNegativeRate
        self.uploadBytesPerSecond = uploadBytesPerSecond.finiteNonNegativeRate
    }
}

extension Double {
    var finiteNonNegativeRate: Double {
        guard isFinite else { return 0 }
        return max(0, self)
    }
}
