import Foundation

/// Rolling-window derivations for the expanded network card, computed from the
/// bounded `NetworkHistory` sparkline buffer. Sibling of `DiskWindowStats`: pure,
/// SwiftUI-free, and fully unit-testable (ADR-005). Reads only local interface
/// rates already in history — no new counters, no privacy surface (PRD).
enum NetworkWindowStats {
    /// Approximate bytes moved over the retained window, integrating each retained
    /// per-second rate over `interval`. A rolling estimate, not a since-launch total
    /// (the buffer only keeps the most recent samples — same caveat as disk).
    static func recentTotalBytes(
        in history: NetworkHistory,
        interval: TimeInterval
    ) -> (download: UInt64, upload: UInt64) {
        guard interval > 0, interval.isFinite else { return (0, 0) }

        let downloadBytes = history.samples.reduce(0.0) { $0 + $1.downloadBytesPerSecond } * interval
        let uploadBytes = history.samples.reduce(0.0) { $0 + $1.uploadBytesPerSecond } * interval

        return (
            download: UInt64(max(0, downloadBytes.rounded())),
            upload: UInt64(max(0, uploadBytes.rounded()))
        )
    }

    /// Highest download/upload rate seen across the retained window. Empty history
    /// yields zeroes rather than `nil` so the detail rows always render a number.
    static func recentPeakRates(in history: NetworkHistory) -> (download: Double, upload: Double) {
        let download = history.samples.map(\.downloadBytesPerSecond).max() ?? 0
        let upload = history.samples.map(\.uploadBytesPerSecond).max() ?? 0
        return (download: download, upload: upload)
    }
}
