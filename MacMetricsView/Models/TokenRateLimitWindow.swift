import Foundation

/// The 5-hour rate-limit block active at a given instant (ADR-006). In-memory,
/// derived per recompute — never persisted.
struct TokenRateLimitBlock: Equatable {
    /// First event's timestamp floored to the hour — matching the round reset
    /// times Claude Code's `/usage` displays.
    let start: Date
    /// `start + 5h`, rendered as "resets at".
    let end: Date
    /// Events in `[start, min(end, now)]`, negative counts clamped. Never negative.
    let usage: TokenAggregate
    /// USD cost of the counted events via `TokenCostCalculator` (ADR-003).
    /// Never negative or NaN.
    let costUSD: Double
}

/// Pure block math over retained raw events (ADR-006): no timers, filesystem, or
/// mutable state. Sibling of `TokenBurnRate`. Blocks are fixed, not rolling: the
/// first event opens a block at its timestamp floored to the hour, the block ends
/// 5 hours later, and the next event at or after that end opens a new floored
/// block. Consumes whatever events it receives — the caller passes Claude-store
/// events only; Codex has different limit semantics and is out of scope.
enum TokenRateLimitWindow {
    static let blockLength: TimeInterval = 5 * 3_600

    /// The block containing `now`, or `nil` when the last block expired before
    /// `now` or there are no events. Determinism within the 25h retention horizon:
    /// any ≥5h gap between events resyncs the chain, so the displayed block never
    /// depends on how much pre-gap history is still retained.
    static func activeBlock(events: [TokenUsageEvent], now: Date) -> TokenRateLimitBlock? {
        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        guard let first = sorted.first else { return nil }

        // Walk the chain, keeping the events of whichever block contains `now`.
        // Blocks are disjoint, so at most one matches.
        var start = floorToHour(first.timestamp)
        var end = start.addingTimeInterval(blockLength)
        var blockEvents: [TokenUsageEvent] = []
        var active: (start: Date, end: Date, events: [TokenUsageEvent])?

        for event in sorted {
            if event.timestamp >= end {
                if start <= now, now < end { active = (start, end, blockEvents) }
                start = floorToHour(event.timestamp)
                end = start.addingTimeInterval(blockLength)
                blockEvents = []
            }
            blockEvents.append(event)
        }
        if start <= now, now < end { active = (start, end, blockEvents) }

        guard let active else { return nil }

        // Usage counts only `[start, min(end, now)]`: an event inside the block
        // window but later than `now` (clock skew) is excluded.
        let counted = active.events.filter { $0.timestamp <= now }
        var usage = TokenAggregate.zero
        for event in counted {
            usage = usage + TokenAggregate(
                input: max(0, event.inputTokens),
                output: max(0, event.outputTokens),
                cacheRead: max(0, event.cacheReadTokens),
                cacheCreation: max(0, event.cacheCreationTokens),
                reasoning: max(0, event.reasoningTokens)
            )
        }
        return TokenRateLimitBlock(
            start: active.start,
            end: active.end,
            usage: usage,
            costUSD: TokenCostCalculator.cost(of: counted).totalUSD
        )
    }

    /// Hour floor on the absolute timeline (timezone-independent for whole-hour
    /// zones), so block starts land on the round HH:00 values `/usage` shows.
    private static func floorToHour(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 3_600).rounded(.down) * 3_600)
    }
}
