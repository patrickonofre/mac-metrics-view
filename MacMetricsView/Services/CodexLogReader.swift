import Foundation
import os

/// Reads OpenAI Codex CLI session logs (`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`),
/// mapping Codex's overlapping cumulative fields into the non-overlapping `TokenUsageEvent`
/// breakdown that reconciles exactly with `total_tokens` (ADR-004).
///
/// Per-file bookkeeping (byte offset + cwd/model/dedup-signature) lives in an
/// `ActiveFileSet<CodexState>`, and the directory walk is scoped to the recent `YYYY/MM/DD`
/// date directories covering the active window plus a midnight-boundary margin — so both the
/// traversal and the per-file read work scale with current activity, and per-file state is
/// evicted once a file ages past the retention tail (ADR-002, ADR-003).
///
/// Token data lives on lines where `type == "event_msg"` and `payload.type ==
/// "token_count"`, under `payload.info.last_token_usage`. Real logs emit each turn's
/// `token_count` event **twice**, so emission is gated on the cumulative
/// `total_token_usage` changing — that dedupe is what guarantees "count each turn once"
/// (the per-turn figures still come from `last_token_usage`). Working directory comes from
/// the first-line `session_meta` (with `turn_context` as a fallback for large files whose
/// header is past the backfill window); the model comes from the latest `turn_context`;
/// the session id is the filename UUID.
///
/// Defensive by design: a missing root yields an empty stream, lines that fail to decode
/// or carry no usable `token_count` are skipped, and a file shorter than its stored offset
/// is treated as rotated and re-read from zero. The first time a file is seen, only the
/// trailing retention window is backfilled — never the whole corpus.
final class CodexLogReader: TokenUsageReading {
    private let rootURL: URL
    private let retentionTail: TimeInterval
    private let maxBackfillBytes: UInt64
    private let now: () -> Date
    private let fileManager: FileManager
    private let calendar: Calendar

    /// Parse state carried per file, collapsing the former four per-file dicts into one record
    /// that is evicted together with the file's offset once it ages out of the active window.
    struct CodexState {
        /// Working directory (from `session_meta`, or a `turn_context` fallback), carried
        /// across incremental reads since the header is only at line 1.
        var cwd: String?
        /// Latest model id seen (from `turn_context`), carried across reads.
        var model: String?
        /// Last emitted dedupe signature (the cumulative total, or a timestamp+total
        /// fallback). Used to drop the duplicate `token_count` event each turn emits.
        var lastSignature: String?
    }

    /// Active-set scan + per-file `(offset, CodexState)` storage, bounded to the active window.
    private var activeSet = ActiveFileSet<CodexState>()

    private var didWarnMissingRoot = false
    private var didWarnClamp = false

    private static let newline: UInt8 = 0x0A
    private static let logger = Logger(subsystem: "MacMetricsView", category: "CodexLogReader")

    init(
        rootURL: URL = CodexLogReader.defaultRootURL,
        retentionTail: TimeInterval = 24 * 60 * 60,
        maxBackfillBytes: UInt64 = 1 * 1024 * 1024,
        fileManager: FileManager = .default,
        timeZone: TimeZone = .current,
        now: @escaping () -> Date = { Date() }
    ) {
        self.rootURL = rootURL
        self.retentionTail = retentionTail
        self.maxBackfillBytes = maxBackfillBytes
        self.fileManager = fileManager
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
        self.now = now
    }

    static var defaultRootURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
    }

    func readNewEvents() -> [TokenUsageEvent] {
        guard fileManager.fileExists(atPath: rootURL.path) else {
            if !didWarnMissingRoot {
                didWarnMissingRoot = true
                Self.logger.debug("Codex sessions root absent at \(self.rootURL.path, privacy: .public)")
            }
            return []
        }
        // Scope the walk to recent date dirs (window + midnight margin); `window ==
        // retentionTail` keeps the skip/evict threshold aligned with the backfill cutoff so
        // eviction is reactivation-safe (ADR-002, ADR-003).
        let active = activeSet.activeFiles(
            roots: recentDateDirs(),
            window: retentionTail,
            now: now(),
            fileManager: fileManager,
            matches: { $0.pathExtension == "jsonl" && $0.lastPathComponent.hasPrefix("rollout-") }
        )
        return active.flatMap { readEvents(from: $0.url, size: $0.size) }
    }

    /// The `~/.codex/sessions/YYYY/MM/DD` directories that can hold a file modified inside the
    /// active window. Covers `ceil(window / day)` days plus a one-day margin so a session
    /// written just before midnight (previous date dir, mtime still in window) is in scope.
    private func recentDateDirs() -> [URL] {
        let today = now()
        let daysBack = Int((retentionTail / 86_400).rounded(.up)) + 1
        var dirs: [URL] = []
        for dayOffset in 0...daysBack {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            guard let year = parts.year, let month = parts.month, let dayOfMonth = parts.day else { continue }
            dirs.append(
                rootURL
                    .appendingPathComponent(String(format: "%04d", year), isDirectory: true)
                    .appendingPathComponent(String(format: "%02d", month), isDirectory: true)
                    .appendingPathComponent(String(format: "%02d", dayOfMonth), isDirectory: true)
            )
        }
        return dirs
    }

    // MARK: - Per-file reading

    /// `size` is the value prefetched by `ActiveFileSet` (no second `stat`).
    private func readEvents(from file: URL, size: UInt64) -> [TokenUsageEvent] {
        let key = file.path

        guard let entry = activeSet[key] else {
            return backfill(file: file, key: key, size: size, state: CodexState())
        }

        if size < entry.offset {                 // rotated / truncated → fresh session state
            return backfill(file: file, key: key, size: size, state: CodexState())
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
    private func backfill(file: URL, key: String, size: UInt64, state initialState: CodexState) -> [TokenUsageEvent] {
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

    /// Parses complete (newline-terminated) lines, threading per-file parse state (cwd,
    /// model, dedupe signature) and emitting one event per *new* turn. Any trailing partial
    /// line is left unconsumed so it is re-read once fully written.
    private func parse(
        _ data: Data,
        file: URL,
        dropFirstPartial: Bool,
        applyTail: Bool,
        state: inout CodexState
    ) -> (events: [TokenUsageEvent], consumed: Int) {
        guard let lastNewline = data.lastIndex(of: Self.newline) else { return ([], 0) }

        let consumable = data[data.startIndex...lastNewline]
        var lines = consumable.split(separator: Self.newline, omittingEmptySubsequences: true)
        if dropFirstPartial, !lines.isEmpty { lines.removeFirst() }

        let cutoff = now().addingTimeInterval(-retentionTail)
        var events: [TokenUsageEvent] = []
        for line in lines {
            guard let event = processLine(Data(line), file: file, state: &state) else { continue }
            if applyTail, event.timestamp < cutoff { continue }
            events.append(event)
        }
        return (events, consumable.count)
    }

    /// Updates per-file state from a single line and returns a token event when the line is
    /// a new turn's `token_count`. `session_meta`/`turn_context` lines update cwd/model and
    /// return `nil`; duplicate or malformed token lines are skipped.
    private func processLine(_ data: Data, file: URL, state: inout CodexState) -> TokenUsageEvent? {
        guard let line = try? Self.decoder.decode(RolloutLine.self, from: data) else { return nil }

        switch line.type {
        case "session_meta":
            if let cwd = line.payload?.cwd, !cwd.isEmpty { state.cwd = cwd }
            return nil
        case "turn_context":
            if let model = line.payload?.model, !model.isEmpty { state.model = model }
            if state.cwd == nil, let cwd = line.payload?.cwd, !cwd.isEmpty { state.cwd = cwd }
            return nil
        case "event_msg":
            return tokenEvent(from: line, file: file, state: &state)
        default:
            return nil
        }
    }

    private func tokenEvent(from line: RolloutLine, file: URL, state: inout CodexState) -> TokenUsageEvent? {
        guard line.payload?.type == "token_count",
              let info = line.payload?.info,
              let last = info.lastTokenUsage,
              let rawTimestamp = line.timestamp,
              let timestamp = Self.parseDate(rawTimestamp)
        else {
            return nil
        }

        // Each turn's token_count is logged twice; gate on the cumulative total so each
        // turn is counted once. Fall back to a timestamp+total signature when the
        // cumulative is absent.
        let signature: String
        if let cumulative = info.totalTokenUsage?.totalTokens {
            signature = "c\(cumulative)"
        } else {
            signature = "l\(rawTimestamp)|\(last.totalTokens ?? 0)"
        }
        guard state.lastSignature != signature else { return nil }
        state.lastSignature = signature

        // Non-overlapping mapping (ADR-004), each subtraction clamped at 0 so a category
        // never goes negative if Codex's subset assumptions ever break.
        let cachedInput = max(0, last.cachedInputTokens ?? 0)
        let rawInput = max(0, last.inputTokens ?? 0)
        let reasoning = max(0, last.reasoningOutputTokens ?? 0)
        let rawOutput = max(0, last.outputTokens ?? 0)

        let input = clampedSubtraction(rawInput, cachedInput)
        let output = clampedSubtraction(rawOutput, reasoning)

        return TokenUsageEvent(
            timestamp: timestamp,
            model: state.model ?? "",
            inputTokens: input,
            outputTokens: output,
            cacheReadTokens: cachedInput,
            cacheCreationTokens: 0,   // Codex has no cache-creation category
            reasoningTokens: reasoning,
            sessionID: Self.sessionID(from: file),
            projectDir: state.cwd ?? ""
        )
    }

    /// `a - b`, clamped at 0. A clamp means Codex broke the documented subset relation
    /// (cached ⊆ input, reasoning ⊆ output) — warn once, since it signals a field-shape change.
    private func clampedSubtraction(_ a: Int, _ b: Int) -> Int {
        guard a >= b else {
            if !didWarnClamp {
                didWarnClamp = true
                Self.logger.debug("Codex token subtraction clamped (a=\(a) < b=\(b)); field shape may have changed")
            }
            return 0
        }
        return a - b
    }

    // MARK: - Decodable line shape

    private struct RolloutLine: Decodable {
        let type: String?
        let timestamp: String?
        let payload: Payload?

        struct Payload: Decodable {
            let type: String?       // event_msg subtype, e.g. "token_count"
            let cwd: String?        // session_meta / turn_context
            let model: String?      // turn_context
            let info: Info?         // event_msg token_count
        }

        struct Info: Decodable {
            let lastTokenUsage: Usage?
            let totalTokenUsage: Usage?
        }

        struct Usage: Decodable {
            let inputTokens: Int?
            let cachedInputTokens: Int?
            let outputTokens: Int?
            let reasoningOutputTokens: Int?
            let totalTokens: Int?
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

    /// The session UUID embedded in a `rollout-<timestamp>-<uuid>.jsonl` filename. The
    /// timestamp itself contains hyphens, so match the canonical UUID pattern rather than
    /// splitting on "-"; fall back to the filename stem if no UUID is present.
    private static func sessionID(from file: URL) -> String {
        let stem = file.deletingPathExtension().lastPathComponent
        guard let match = stem.range(of: Self.uuidPattern, options: .regularExpression) else {
            return stem
        }
        return String(stem[match])
    }

    private static let uuidPattern =
        "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"

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
