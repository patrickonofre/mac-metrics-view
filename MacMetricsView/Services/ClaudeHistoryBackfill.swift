import Foundation

/// One-shot, read-only scan of the Claude session logs that seeds the daily
/// ledger with the 7 days *before today* (ADR-007). Today is structurally
/// excluded — it belongs to live ingest, so backfill and ingest can never
/// double-count. Triggered once from `CPUState`, guarded by a persisted flag.
///
/// Side-effect-free: it never touches reader offsets, `ActiveFileSet` state, or
/// any store — the only write is the caller's ledger merge. Defensive like the
/// reader: malformed lines, truncated files, and unreadable files contribute
/// zero and never throw. Line parsing is the shared `ClaudeLogLineParser`, so
/// backfill and the incremental reader cannot drift.
struct ClaudeHistoryBackfill {
    private let rootURL: URL
    private let calendar: Calendar
    private let fileManager: FileManager

    init(
        rootURL: URL = ClaudeCodeLogReader.defaultRootURL,
        calendar: Calendar = .current,
        fileManager: FileManager = .default
    ) {
        self.rootURL = rootURL
        self.calendar = calendar
        self.fileManager = fileManager
    }

    /// Per-day usage + ingest-time cost for events in
    /// `[start of today − 7 days, start of today)`, keyed like the ledger.
    /// Files whose mtime predates the window are skipped unread — the 7-day
    /// timestamp filter bounds the first-run I/O burst.
    func scan(now: Date) -> [String: TokenDailyLedger.DayEntry] {
        let todayStart = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .day, value: -7, to: todayStart) else { return [:] }
        guard fileManager.fileExists(atPath: rootURL.path) else { return [:] }
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
        ) else { return [:] }

        var seeded: [String: TokenDailyLedger.DayEntry] = [:]
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            if values?.isRegularFile == false { continue }
            // A file last written before the window holds nothing newer; an
            // unreadable mtime falls through to reading — correctness never
            // depends on the skip.
            if let mtime = values?.contentModificationDate, mtime < windowStart { continue }

            scanFile(url, windowStart: windowStart, todayStart: todayStart, into: &seeded)
        }
        return seeded
    }

    private func scanFile(
        _ file: URL,
        windowStart: Date,
        todayStart: Date,
        into seeded: inout [String: TokenDailyLedger.DayEntry]
    ) {
        guard let data = try? Data(contentsOf: file) else { return }

        // Same dedup rule as the reader: message ids counted once per file.
        var seenMessageIDs = Set<String>()
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            guard let event = ClaudeLogLineParser.parseLine(Data(line), file: file, seenMessageIDs: &seenMessageIDs) else { continue }
            guard event.timestamp >= windowStart, event.timestamp < todayStart else { continue }

            let key = TokenDailyLedger.dayKey(for: event.timestamp, calendar: calendar)
            var entry = seeded[key] ?? TokenDailyLedger.DayEntry(usage: .zero, costUSD: 0)
            entry.usage = entry.usage.adding(event)
            entry.costUSD += TokenCostCalculator.cost(of: [event]).totalUSD
            seeded[key] = entry
        }
    }
}
