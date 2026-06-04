import Foundation

/// Reads Claude Code session logs (`~/.claude/projects/<project>/<session>.jsonl`).
///
/// Per-file bookkeeping (byte offset + dedup set) lives in an `ActiveFileSet<ClaudeState>`,
/// so each poll only opens files that are currently active and reader memory stays bounded to
/// the active window — dormant sessions cost one prefetched `stat` and no read, and their
/// state is evicted once they age past the retention tail (ADR-002, ADR-003).
///
/// Defensive by design: a missing root yields an empty stream, lines that fail to decode
/// or lack `message.usage` are skipped without aborting the pass, and a file shorter than
/// its stored offset is treated as rotated and re-read from zero. The first time a file is
/// seen, only the trailing retention window is backfilled — never the whole corpus.
final class ClaudeCodeLogReader: TokenUsageReading {
    private let rootURL: URL
    private let retentionTail: TimeInterval
    private let maxBackfillBytes: UInt64
    private let now: () -> Date
    private let fileManager: FileManager

    /// Parse state carried per file. The dedup set is scoped to a single file (replacing the
    /// former global set) and is evicted with the file's other state, so total dedup memory
    /// scales with the active set rather than with lifetime history (ADR-003).
    ///
    /// Claude Code writes one JSONL line per assistant content-block (each `tool_use`),
    /// repeating the same `message.usage` on every line, so summing all of them double-counts
    /// a single message's tokens. We count each `message.id` once; lines without an id (e.g.
    /// synthetic) are never deduped.
    struct ClaudeState {
        var seenMessageIDs: Set<String> = []
    }

    /// Active-set scan + per-file `(offset, ClaudeState)` storage, bounded to the active window.
    private var activeSet = ActiveFileSet<ClaudeState>()

    private static let newline: UInt8 = 0x0A

    init(
        rootURL: URL = ClaudeCodeLogReader.defaultRootURL,
        retentionTail: TimeInterval = 24 * 60 * 60,
        maxBackfillBytes: UInt64 = 1 * 1024 * 1024,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = { Date() }
    ) {
        self.rootURL = rootURL
        self.retentionTail = retentionTail
        self.maxBackfillBytes = maxBackfillBytes
        self.fileManager = fileManager
        self.now = now
    }

    static var defaultRootURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }

    func readNewEvents() -> [TokenUsageEvent] {
        // `window == retentionTail` so the skip/evict threshold matches the backfill cutoff,
        // keeping eviction reactivation-safe (ADR-003).
        let active = activeSet.activeFiles(
            roots: [rootURL],
            window: retentionTail,
            now: now(),
            fileManager: fileManager,
            matches: { $0.pathExtension == "jsonl" }
        )
        return active.flatMap { readEvents(from: $0.url, size: $0.size) }
    }

    // MARK: - Per-file reading

    /// `size` is the value prefetched by `ActiveFileSet` (no second `stat`). Only files that
    /// have actually grown are opened; an unchanged active file short-circuits before any read.
    private func readEvents(from file: URL, size: UInt64) -> [TokenUsageEvent] {
        let key = file.path

        guard let entry = activeSet[key] else {
            return backfill(file: file, key: key, size: size, state: ClaudeState())
        }

        if size < entry.offset {                 // rotated / truncated
            // Dedup state is intentionally preserved across rotation (matches the prior global
            // set's behavior); backfill re-seeds the offset from EOF.
            return backfill(file: file, key: key, size: size, state: entry.state)
        }
        if size == entry.offset { return [] }    // nothing appended

        guard let data = readData(from: file, start: entry.offset) else { return [] }
        var state = entry.state
        let parsed = parse(data, file: file, dropFirstPartial: false, applyTail: false, state: &state)
        activeSet[key] = .init(offset: entry.offset + UInt64(parsed.consumed), state: state)
        return parsed.events
    }

    /// Seeds the offset to EOF and returns only events inside the retention tail, reading
    /// at most `maxBackfillBytes` from the end so cold start never ingests the full file.
    private func backfill(file: URL, key: String, size: UInt64, state initialState: ClaudeState) -> [TokenUsageEvent] {
        let start = size > maxBackfillBytes ? size - maxBackfillBytes : 0
        var state = initialState
        guard let data = readData(from: file, start: start) else {
            activeSet[key] = .init(offset: size, state: state)
            return []
        }
        let parsed = parse(data, file: file, dropFirstPartial: start > 0, applyTail: true, state: &state)
        activeSet[key] = .init(offset: start + UInt64(parsed.consumed), state: state)
        return parsed.events
    }

    // MARK: - Parsing

    /// Parses complete (newline-terminated) lines from `data`, returning the events and the
    /// number of bytes consumed up to and including the last newline. Any trailing partial
    /// line is left unconsumed so it is re-read once fully written.
    private func parse(
        _ data: Data,
        file: URL,
        dropFirstPartial: Bool,
        applyTail: Bool,
        state: inout ClaudeState
    ) -> (events: [TokenUsageEvent], consumed: Int) {
        guard let lastNewline = data.lastIndex(of: Self.newline) else { return ([], 0) }

        let consumable = data[data.startIndex...lastNewline]
        var lines = consumable.split(separator: Self.newline, omittingEmptySubsequences: true)
        if dropFirstPartial, !lines.isEmpty { lines.removeFirst() }

        let cutoff = now().addingTimeInterval(-retentionTail)
        var events: [TokenUsageEvent] = []
        for line in lines {
            guard let event = parseLine(Data(line), file: file, state: &state) else { continue }
            if applyTail, event.timestamp < cutoff { continue }
            events.append(event)
        }
        return (events, consumable.count)
    }

    private func parseLine(_ data: Data, file: URL, state: inout ClaudeState) -> TokenUsageEvent? {
        guard let line = try? Self.decoder.decode(LogLine.self, from: data),
              let usage = line.message?.usage,
              let rawTimestamp = line.timestamp,
              let timestamp = Self.parseDate(rawTimestamp)
        else {
            return nil
        }

        // One usage record per assistant message: skip repeated content-block lines that
        // carry the same already-counted message id (per file, ADR-003).
        if let messageID = line.message?.id {
            guard !state.seenMessageIDs.contains(messageID) else { return nil }
            state.seenMessageIDs.insert(messageID)
        }

        return TokenUsageEvent(
            timestamp: timestamp,
            model: line.message?.model ?? "",
            inputTokens: usage.inputTokens ?? 0,
            outputTokens: usage.outputTokens ?? 0,
            cacheReadTokens: usage.cacheReadInputTokens ?? 0,
            cacheCreationTokens: usage.cacheCreationInputTokens ?? 0,
            reasoningTokens: 0,   // Claude Code has no reasoning-token category (ADR-002)
            sessionID: file.deletingPathExtension().lastPathComponent,
            projectDir: file.deletingLastPathComponent().lastPathComponent
        )
    }

    private struct LogLine: Decodable {
        let timestamp: String?
        let message: Message?

        struct Message: Decodable {
            let id: String?
            let model: String?
            let usage: Usage?
        }

        struct Usage: Decodable {
            let inputTokens: Int?
            let outputTokens: Int?
            let cacheReadInputTokens: Int?
            let cacheCreationInputTokens: Int?
        }
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private static let isoWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func parseDate(_ string: String) -> Date? {
        isoWithFractional.date(from: string) ?? isoPlain.date(from: string)
    }

    // MARK: - Filesystem helpers

    private func readData(from file: URL, start: UInt64) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: start)
            return try handle.readToEnd() ?? Data()
        } catch {
            return nil
        }
    }
}
