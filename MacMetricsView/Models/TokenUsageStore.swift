import Foundation

/// Bounded, timestamped event store backing the rolling token windows, plus a
/// since-reset accumulator kept as running sums (ADR-003).
///
/// Raw events are retained only for the longest rolling window (24h) plus headroom;
/// older events are evicted on append. The since-reset figure is stored as per-scope
/// sums rather than raw events, so it survives eviction and can span arbitrary
/// durations without unbounded memory. This type performs no windowing/aggregation
/// math — that belongs to `TokenWindowStats`.
struct TokenUsageStore: Equatable {
    /// 24h rolling window + 1h headroom so events near the window boundary are not
    /// dropped a moment too early.
    static let defaultRetentionHorizon: TimeInterval = 25 * 60 * 60

    let retentionHorizon: TimeInterval
    private(set) var events: [TokenUsageEvent]
    private(set) var resetAt: Date

    /// Newest event timestamp seen, tracked incrementally so eviction is O(1) to anchor
    /// instead of an O(n) `.max()` per append (OPT-04). Invariant: eviction only removes
    /// events strictly older than `newest - horizon`, so it can never drop the newest —
    /// this field therefore stays valid without a rescan. No path removes events except
    /// `evictExpired`, which preserves that invariant.
    private(set) var newestTimestamp: Date?

    /// Since-reset sums for the whole machine.
    private(set) var sinceResetGlobal: TokenAggregate
    /// Since-reset sums keyed by `projectDir`; the current-project sum is resolved by MRU.
    private(set) var sinceResetByProject: [String: TokenAggregate]
    /// Since-reset sums keyed by `sessionID`; the current-session sum is resolved by MRU.
    private(set) var sinceResetBySession: [String: TokenAggregate]

    init(
        resetAt: Date,
        retentionHorizon: TimeInterval = TokenUsageStore.defaultRetentionHorizon,
        events: [TokenUsageEvent] = [],
        sinceResetGlobal: TokenAggregate = .zero,
        sinceResetByProject: [String: TokenAggregate] = [:],
        sinceResetBySession: [String: TokenAggregate] = [:]
    ) {
        self.retentionHorizon = max(0, retentionHorizon)
        self.resetAt = resetAt
        self.events = events
        self.newestTimestamp = events.map(\.timestamp).max()
        self.sinceResetGlobal = sinceResetGlobal
        self.sinceResetByProject = sinceResetByProject
        self.sinceResetBySession = sinceResetBySession
        evictExpired()
    }

    /// Appends one event, evicting anything older than the retention horizon relative
    /// to the newest event, and folds the event into the since-reset sums when it
    /// occurs at or after `resetAt`.
    mutating func append(_ event: TokenUsageEvent) {
        events.append(event)
        foldSinceReset(event)
        trackNewest(event)
        evictExpired()
    }

    /// Appends a whole batch, folding each event's since-reset sums but evicting only
    /// **once** at the end (OPT-04). Equivalent final state to calling `append(_:)` per
    /// event, at O(n) eviction instead of O(k·n): eviction is order-independent and no
    /// reader consumes the store mid-batch (all main-actor; `recompute()` runs after).
    mutating func append(contentsOf newEvents: [TokenUsageEvent]) {
        guard !newEvents.isEmpty else { return }
        for event in newEvents {
            events.append(event)
            foldSinceReset(event)
            trackNewest(event)
        }
        evictExpired()
    }

    /// Starts a fresh since-reset measurement: stamps `resetAt` and zeroes every
    /// accumulator. Raw events (and therefore the rolling windows) are left untouched.
    mutating func reset(now: Date) {
        resetAt = now
        sinceResetGlobal = .zero
        sinceResetByProject = [:]
        sinceResetBySession = [:]
    }

    /// Folds one event into the since-reset sums when it occurs at or after `resetAt`.
    private mutating func foldSinceReset(_ event: TokenUsageEvent) {
        guard event.timestamp >= resetAt else { return }
        sinceResetGlobal = sinceResetGlobal.adding(event)
        sinceResetByProject[event.projectDir] =
            (sinceResetByProject[event.projectDir] ?? .zero).adding(event)
        sinceResetBySession[event.sessionID] =
            (sinceResetBySession[event.sessionID] ?? .zero).adding(event)
    }

    /// Advances `newestTimestamp` incrementally; order-independent (`max`).
    private mutating func trackNewest(_ event: TokenUsageEvent) {
        newestTimestamp = max(newestTimestamp ?? event.timestamp, event.timestamp)
    }

    private mutating func evictExpired() {
        guard let newest = newestTimestamp else { return }
        let cutoff = newest.addingTimeInterval(-retentionHorizon)
        events.removeAll { $0.timestamp < cutoff }
    }
}

extension TokenAggregate {
    static let zero = TokenAggregate(input: 0, output: 0, cacheRead: 0, cacheCreation: 0, reasoning: 0)

    /// Returns a copy with this event's token counts folded in. Pure value math.
    func adding(_ event: TokenUsageEvent) -> TokenAggregate {
        TokenAggregate(
            input: input + event.inputTokens,
            output: output + event.outputTokens,
            cacheRead: cacheRead + event.cacheReadTokens,
            cacheCreation: cacheCreation + event.cacheCreationTokens,
            reasoning: reasoning + event.reasoningTokens
        )
    }
}
