import Foundation

/// Pure aggregation over a `TokenUsageStore`: turns (store, scope, window, now) into a
/// `TokenAggregate`, and into per-bucket totals for the sparkline (ADR-003).
///
/// Sibling of `DiskWindowStats`. Contains all timestamp/scope filtering math and no
/// timers or filesystem access — `now` is always injected. Scope is resolved by MRU:
/// the source file of the most-recently-timestamped event stands in for the
/// most-recently-modified `.jsonl`, so `session`/`project` need no `stat` here.
enum TokenWindowStats {

    static func aggregate(
        store: TokenUsageStore,
        scope: TokenScope,
        window: TokenWindow,
        now: Date
    ) -> TokenAggregate {
        if window == .sinceReset {
            return sinceReset(store: store, scope: scope)
        }

        let start = windowStart(window, now: now)
        let mru = mostRecentlyUsed(in: store.events)

        return store.events
            .filter { $0.timestamp >= start && matches(scope: scope, event: $0, mru: mru) }
            .reduce(TokenAggregate.zero) { $0.adding($1) }
    }

    /// Per-bucket total-token counts across the window's `[start, now]` range, oldest
    /// bucket first. Suitable as `SparklineView` input after the caller normalizes to a
    /// 0–100 range.
    static func sparklineBuckets(
        store: TokenUsageStore,
        scope: TokenScope,
        window: TokenWindow,
        now: Date,
        bucketCount: Int = 45
    ) -> [Int] {
        guard bucketCount > 0 else { return [] }

        let start = sparklineStart(store: store, window: window, now: now)
        var buckets = [Int](repeating: 0, count: bucketCount)
        let span = now.timeIntervalSince(start)
        guard span > 0 else { return buckets }

        let width = span / Double(bucketCount)
        let mru = mostRecentlyUsed(in: store.events)

        for event in store.events where matches(scope: scope, event: event, mru: mru) {
            let offset = event.timestamp.timeIntervalSince(start)
            guard offset >= 0, event.timestamp <= now else { continue }
            let index = min(bucketCount - 1, Int(offset / width))
            buckets[index] += totalTokens(event)
        }

        return buckets
    }

    // MARK: - Scope / MRU

    private static func mostRecentlyUsed(
        in events: [TokenUsageEvent]
    ) -> (sessionID: String, projectDir: String)? {
        guard let newest = events.max(by: { $0.timestamp < $1.timestamp }) else { return nil }
        return (newest.sessionID, newest.projectDir)
    }

    private static func matches(
        scope: TokenScope,
        event: TokenUsageEvent,
        mru: (sessionID: String, projectDir: String)?
    ) -> Bool {
        switch scope {
        case .global:
            return true
        case .session:
            return event.sessionID == mru?.sessionID
        case .project:
            return event.projectDir == mru?.projectDir
        }
    }

    private static func sinceReset(store: TokenUsageStore, scope: TokenScope) -> TokenAggregate {
        let mru = mostRecentlyUsed(in: store.events)
        switch scope {
        case .global:
            return store.sinceResetGlobal
        case .project:
            guard let dir = mru?.projectDir else { return .zero }
            return store.sinceResetByProject[dir] ?? .zero
        case .session:
            guard let id = mru?.sessionID else { return .zero }
            return store.sinceResetBySession[id] ?? .zero
        }
    }

    // MARK: - Window bounds

    private static func windowStart(_ window: TokenWindow, now: Date) -> Date {
        switch window {
        case .today:
            return Calendar.current.startOfDay(for: now)
        case .lastHour:
            return now.addingTimeInterval(-3_600)
        case .last24h:
            return now.addingTimeInterval(-86_400)
        case .sinceReset:
            return now   // not used; sinceReset routes to the accumulator
        }
    }

    private static func sparklineStart(
        store: TokenUsageStore,
        window: TokenWindow,
        now: Date
    ) -> Date {
        switch window {
        case .today, .lastHour, .last24h:
            return windowStart(window, now: now)
        case .sinceReset:
            // Raw events only exist within the retention horizon, so the sparkline cannot
            // show anything older even if the reset was days ago.
            let horizonStart = now.addingTimeInterval(-store.retentionHorizon)
            return max(store.resetAt, horizonStart)
        }
    }

    private static func totalTokens(_ event: TokenUsageEvent) -> Int {
        event.inputTokens + event.outputTokens + event.cacheReadTokens + event.cacheCreationTokens
    }
}
