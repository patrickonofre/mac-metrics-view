import Foundation

struct DiskCounterSnapshot: Equatable {
    let timestamp: Date
    let bytesRead: UInt64
    let bytesWritten: UInt64

    init(timestamp: Date = Date(), bytesRead: UInt64, bytesWritten: UInt64) {
        self.timestamp = timestamp
        self.bytesRead = bytesRead
        self.bytesWritten = bytesWritten
    }
}
