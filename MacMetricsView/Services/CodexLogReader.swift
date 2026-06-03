import Foundation
import os

/// Reads OpenAI Codex CLI session logs (`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`),
/// tracking per-file byte offsets so each poll only parses newly appended lines, and maps
/// Codex's overlapping cumulative fields into the non-overlapping `TokenUsageEvent`
/// breakdown that reconciles exactly with `total_tokens` (ADR-004).
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

    /// Byte offset already consumed per file, keyed by path. `nil` means never seen.
    private var offsets: [String: UInt64] = [:]
    /// Working directory captured per file (from `session_meta`, or a `turn_context`
    /// fallback), carried across incremental reads since the header is only at line 1.
    private var cwdByFile: [String: String] = [:]
    /// Latest model id seen per file (from `turn_context`), carried across reads.
    private var modelByFile: [String: String] = [:]
    /// Last emitted dedupe signature per file (the cumulative total, or a timestamp+total
    /// fallback). Used to drop the duplicate `token_count` event each turn emits.
    private var lastSignatureByFile: [String: String] = [:]

    private var didWarnMissingRoot = false
    private var didWarnClamp = false

    private static let newline: UInt8 = 0x0A
    private static let logger = Logger(subsystem: "MacMetricsView", category: "CodexLogReader")

    init(
        rootURL: URL = CodexLogReader.defaultRootURL,
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
            .appendingPathComponent(".codex/sessions", isDirectory: true)
    }

    func readNewEvents() -> [TokenUsageEvent] {
        guard let files = rolloutFiles() else { return [] }
        return files.flatMap { readEvents(from: $0) }
    }

    // MARK: - Per-file reading

    private func readEvents(from file: URL) -> [TokenUsageEvent] {
        guard let size = fileSize(file) else { return [] }
        let key = file.path

        guard let known = offsets[key] else {
            return backfill(file: file, key: key, size: size)
        }

        if size < known {                       // rotated / truncated
            resetFileState(key)
            return backfill(file: file, key: key, size: size)
        }
        if size == known { return [] }          // nothing appended

        guard let data = readData(from: file, start: known) else { return [] }
        let parsed = parse(data, file: file, dropFirstPartial: false, applyTail: false)
        offsets[key] = known + UInt64(parsed.consumed)
        return parsed.events
    }

    /// Seeds the offset to EOF and returns only events inside the retention tail, reading
    /// at most `maxBackfillBytes` from the end so cold start never ingests the full file.
    private func backfill(file: URL, key: String, size: UInt64) -> [TokenUsageEvent] {
        let start = size > maxBackfillBytes ? size - maxBackfillBytes : 0
        guard let data = readData(from: file, start: start) else {
            offsets[key] = size
            return []
        }
        let parsed = parse(data, file: file, dropFirstPartial: start > 0, applyTail: true)
        offsets[key] = start + UInt64(parsed.consumed)
        return parsed.events
    }

    private func resetFileState(_ key: String) {
        offsets[key] = 0
        cwdByFile[key] = nil
        modelByFile[key] = nil
        lastSignatureByFile[key] = nil
    }

    // MARK: - Parsing

    /// Parses complete (newline-terminated) lines, threading per-file parse state (cwd,
    /// model, dedupe signature) and emitting one event per *new* turn. Any trailing partial
    /// line is left unconsumed so it is re-read once fully written.
    private func parse(
        _ data: Data,
        file: URL,
        dropFirstPartial: Bool,
        applyTail: Bool
    ) -> (events: [TokenUsageEvent], consumed: Int) {
        guard let lastNewline = data.lastIndex(of: Self.newline) else { return ([], 0) }

        let consumable = data[data.startIndex...lastNewline]
        var lines = consumable.split(separator: Self.newline, omittingEmptySubsequences: true)
        if dropFirstPartial, !lines.isEmpty { lines.removeFirst() }

        let cutoff = now().addingTimeInterval(-retentionTail)
        let key = file.path
        var events: [TokenUsageEvent] = []
        for line in lines {
            guard let event = processLine(Data(line), file: file, key: key) else { continue }
            if applyTail, event.timestamp < cutoff { continue }
            events.append(event)
        }
        return (events, consumable.count)
    }

    /// Updates per-file state from a single line and returns a token event when the line is
    /// a new turn's `token_count`. `session_meta`/`turn_context` lines update cwd/model and
    /// return `nil`; duplicate or malformed token lines are skipped.
    private func processLine(_ data: Data, file: URL, key: String) -> TokenUsageEvent? {
        guard let line = try? Self.decoder.decode(RolloutLine.self, from: data) else { return nil }

        switch line.type {
        case "session_meta":
            if let cwd = line.payload?.cwd, !cwd.isEmpty { cwdByFile[key] = cwd }
            return nil
        case "turn_context":
            if let model = line.payload?.model, !model.isEmpty { modelByFile[key] = model }
            if cwdByFile[key] == nil, let cwd = line.payload?.cwd, !cwd.isEmpty { cwdByFile[key] = cwd }
            return nil
        case "event_msg":
            return tokenEvent(from: line, file: file, key: key)
        default:
            return nil
        }
    }

    private func tokenEvent(from line: RolloutLine, file: URL, key: String) -> TokenUsageEvent? {
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
        guard lastSignatureByFile[key] != signature else { return nil }
        lastSignatureByFile[key] = signature

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
            model: modelByFile[key] ?? "",
            inputTokens: input,
            outputTokens: output,
            cacheReadTokens: cachedInput,
            cacheCreationTokens: 0,   // Codex has no cache-creation category
            reasoningTokens: reasoning,
            sessionID: Self.sessionID(from: file),
            projectDir: cwdByFile[key] ?? ""
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

    private func rolloutFiles() -> [URL]? {
        guard fileManager.fileExists(atPath: rootURL.path) else {
            if !didWarnMissingRoot {
                didWarnMissingRoot = true
                Self.logger.debug("Codex sessions root absent at \(self.rootURL.path, privacy: .public)")
            }
            return nil
        }
        guard let enumerator = fileManager.enumerator(at: rootURL, includingPropertiesForKeys: nil) else {
            return []
        }
        var files: [URL] = []
        for case let url as URL in enumerator
        where url.pathExtension == "jsonl" && url.lastPathComponent.hasPrefix("rollout-") {
            files.append(url)
        }
        return files
    }

    private func fileSize(_ file: URL) -> UInt64? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: file.path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value
        else {
            return nil
        }
        return size
    }

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
