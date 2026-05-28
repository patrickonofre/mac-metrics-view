import Foundation

enum DiskSampleCalculator {
    static func sample(
        previous: DiskCounterSnapshot,
        current: DiskCounterSnapshot
    ) -> DiskSample? {
        guard current.bytesRead >= previous.bytesRead,
              current.bytesWritten >= previous.bytesWritten
        else {
            return nil
        }

        let elapsedSeconds = current.timestamp.timeIntervalSince(previous.timestamp)
        guard elapsedSeconds > 0, elapsedSeconds.isFinite else { return nil }

        let readRate = Double(current.bytesRead - previous.bytesRead) / elapsedSeconds
        let writeRate = Double(current.bytesWritten - previous.bytesWritten) / elapsedSeconds

        guard readRate.isFinite,
              writeRate.isFinite,
              readRate >= 0,
              writeRate >= 0
        else {
            return nil
        }

        return DiskSample(
            timestamp: current.timestamp,
            readBytesPerSecond: readRate,
            writeBytesPerSecond: writeRate
        )
    }
}
