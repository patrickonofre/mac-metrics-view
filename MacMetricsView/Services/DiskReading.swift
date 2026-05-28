import Foundation

protocol DiskReading {
    func readSnapshot() -> DiskCounterSnapshot?
}
