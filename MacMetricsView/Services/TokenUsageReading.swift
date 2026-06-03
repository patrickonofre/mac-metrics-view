import Foundation

/// Reads newly appended Claude Code usage events since the last poll.
///
/// Implementations track per-file byte offsets and skip unparseable lines. The first
/// call seeds offsets and backfills only the bounded retention window (not all history).
protocol TokenUsageReading {
    func readNewEvents() -> [TokenUsageEvent]
}
