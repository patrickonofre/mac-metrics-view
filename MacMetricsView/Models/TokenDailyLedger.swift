import Foundation

/// Persisted per-day Claude usage + estimated-cost buckets backing the weekly
/// rate-limit figure (ADR-007). Keys are `"yyyy-MM-dd"` in the injected (local)
/// calendar; the rolling week is today plus the 7 prior days.
///
/// A pure value type like `TokenUsageStore`: `Calendar` always injected, no
/// `UserDefaults`, no I/O — persistence (JSON in `UserDefaults`) happens at the
/// `CPUState` boundary. Cost is taken as passed in, computed at ingest with the
/// price table in effect then (ADR-007: past days are never repriced).
struct TokenDailyLedger: Equatable, Codable {
    struct DayEntry: Equatable, Codable {
        var usage: TokenAggregate
        var costUSD: Double
    }

    private(set) var days: [String: DayEntry]

    init(days: [String: DayEntry] = [:]) {
        self.days = days
    }

    /// Accumulates the event into the bucket of its timestamp's local-calendar day.
    /// Negative or non-finite cost clamps to zero — a bucket can never go negative.
    mutating func fold(_ event: TokenUsageEvent, costUSD: Double, calendar: Calendar) {
        let key = Self.dayKey(for: event.timestamp, calendar: calendar)
        var entry = days[key] ?? DayEntry(usage: .zero, costUSD: 0)
        entry.usage = entry.usage.adding(event)
        entry.costUSD += costUSD.isFinite ? max(0, costUSD) : 0
        days[key] = entry
    }

    /// Backfill merge: replaces a day bucket with the scan's complete view of it.
    /// The scan supersedes any partial slice live ingest may have folded from the
    /// reader's cold-start tail, so replacing — not adding — is what keeps the
    /// first run free of double counts (ADR-007).
    mutating func replaceDay(_ key: String, with entry: DayEntry) {
        days[key] = entry
    }

    /// Drops every bucket outside today + the 7 prior days (rolling 8 entries).
    mutating func prune(now: Date, calendar: Calendar) {
        let kept = Self.weekKeys(now: now, calendar: calendar)
        days = days.filter { kept.contains($0.key) }
    }

    /// Sum of the trailing 7 daily buckets plus today (rolling window — no
    /// account-specific anchor, ADR-007).
    func weeklyTotal(now: Date, calendar: Calendar) -> (usage: TokenAggregate, costUSD: Double) {
        let counted = Self.weekKeys(now: now, calendar: calendar)
        var usage = TokenAggregate.zero
        var cost = 0.0
        for (key, entry) in days where counted.contains(key) {
            usage = usage + entry.usage
            cost += entry.costUSD
        }
        return (usage, cost)
    }

    /// `"yyyy-MM-dd"` in the injected calendar — deterministic, no formatter state.
    static func dayKey(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Keys of today + the 7 prior days relative to `now`.
    private static func weekKeys(now: Date, calendar: Calendar) -> Set<String> {
        var keys = Set<String>()
        for daysBack in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: -daysBack, to: now) else { continue }
            keys.insert(dayKey(for: day, calendar: calendar))
        }
        return keys
    }
}
