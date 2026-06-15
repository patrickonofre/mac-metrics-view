import Foundation

/// Cumulative two-direction byte totals accumulated since app launch, for the network
/// (download/upload) and disk (read/write) detail cards. Unlike the rolling-window
/// `…WindowStats`, this is a since-launch running total: each tick adds `rate × elapsed`
/// where `elapsed` is the real gap between consecutive sample timestamps — and since a
/// sample's rate is `byteDelta / elapsed`, that product recovers the exact byte delta,
/// so the total is accurate rather than an interval approximation. In-memory only (no
/// persistence): the count resets to zero each launch. Pure and testable (ADR-005).
struct TrafficSessionTotals: Equatable {
    private(set) var inboundBytes: Double = 0
    private(set) var outboundBytes: Double = 0

    /// Folds one sample's rates over the elapsed gap since the previous sample. A
    /// non-positive or non-finite gap is ignored (e.g. the first sample, or a clock
    /// glitch); negative/NaN rates contribute nothing, so the totals never go backward.
    mutating func add(inboundRate: Double, outboundRate: Double, elapsed: TimeInterval) {
        guard elapsed > 0, elapsed.isFinite else { return }
        if inboundRate.isFinite, inboundRate > 0 { inboundBytes += inboundRate * elapsed }
        if outboundRate.isFinite, outboundRate > 0 { outboundBytes += outboundRate * elapsed }
    }

    /// Rounded, non-negative byte counts for formatting.
    var inbound: UInt64 { UInt64(max(0, inboundBytes.rounded())) }
    var outbound: UInt64 { UInt64(max(0, outboundBytes.rounded())) }
}
