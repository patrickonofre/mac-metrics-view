import Foundation

/// Rolling-window derivations for the expanded network card, computed from the
/// bounded `NetworkHistory` sparkline buffer. Sibling of `DiskWindowStats`: pure,
/// SwiftUI-free, and fully unit-testable (ADR-005). Reads only local interface
/// rates already in history — no new counters, no privacy surface (PRD).
enum NetworkWindowStats {
    /// Integrate each retained rate over its measured interval, falling back to
    /// `interval` for samples without a recorded measurement duration.
    static func recentTotalBytes(
        in history: NetworkHistory,
        interval: TimeInterval
    ) -> (download: UInt64, upload: UInt64) {
        var totals = TrafficSessionTotals()
        for sample in history.samples {
            totals.add(inboundRate: sample.downloadBytesPerSecond, outboundRate: sample.uploadBytesPerSecond,
                       elapsed: sample.measurementInterval ?? interval)
        }
        return (download: totals.inbound, upload: totals.outbound)
    }

    /// Highest download/upload rate seen across the retained window. Empty history
    /// yields zeroes rather than `nil` so the detail rows always render a number.
    static func recentPeakRates(in history: NetworkHistory) -> (download: Double, upload: Double) {
        let download = history.samples.map(\.downloadBytesPerSecond).max() ?? 0
        let upload = history.samples.map(\.uploadBytesPerSecond).max() ?? 0
        return (download: download, upload: upload)
    }
}
