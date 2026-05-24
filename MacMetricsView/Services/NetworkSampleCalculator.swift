import Foundation

enum NetworkSampleCalculator {
    static func sample(
        previous: NetworkCounterSnapshot,
        current: NetworkCounterSnapshot
    ) -> NetworkSample? {
        guard current.receivedBytes >= previous.receivedBytes,
              current.sentBytes >= previous.sentBytes
        else {
            return nil
        }

        let elapsedSeconds = current.timestamp.timeIntervalSince(previous.timestamp)
        guard elapsedSeconds > 0, elapsedSeconds.isFinite else { return nil }

        let downloadRate = Double(current.receivedBytes - previous.receivedBytes) / elapsedSeconds
        let uploadRate = Double(current.sentBytes - previous.sentBytes) / elapsedSeconds

        guard downloadRate.isFinite,
              uploadRate.isFinite,
              downloadRate >= 0,
              uploadRate >= 0
        else {
            return nil
        }

        return NetworkSample(
            timestamp: current.timestamp,
            downloadBytesPerSecond: downloadRate,
            uploadBytesPerSecond: uploadRate
        )
    }
}
