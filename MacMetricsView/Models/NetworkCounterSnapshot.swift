import Foundation

struct NetworkCounterSnapshot: Equatable {
    let timestamp: Date
    let receivedBytes: UInt64
    let sentBytes: UInt64

    init(timestamp: Date = Date(), receivedBytes: UInt64, sentBytes: UInt64) {
        self.timestamp = timestamp
        self.receivedBytes = receivedBytes
        self.sentBytes = sentBytes
    }
}
