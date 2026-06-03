import Foundation

/// Reads Claude Code session logs (`~/.claude/projects/<project>/<session>.jsonl`),
/// tracking per-file byte offsets so each poll only parses newly appended lines (ADR-002).
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

    /// Byte offset already consumed per file, keyed by path. `nil` means never seen.
    private var offsets: [String: UInt64] = [:]

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
        guard let files = jsonlFiles() else { return [] }
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
            offsets[key] = 0
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

    // MARK: - Parsing

    /// Parses complete (newline-terminated) lines from `data`, returning the events and the
    /// number of bytes consumed up to and including the last newline. Any trailing partial
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
        var events: [TokenUsageEvent] = []
        for line in lines {
            guard let event = parseLine(Data(line), file: file) else { continue }
            if applyTail, event.timestamp < cutoff { continue }
            events.append(event)
        }
        return (events, consumable.count)
    }

    private func parseLine(_ data: Data, file: URL) -> TokenUsageEvent? {
        guard let line = try? Self.decoder.decode(LogLine.self, from: data),
              let usage = line.message?.usage,
              let rawTimestamp = line.timestamp,
              let timestamp = Self.parseDate(rawTimestamp)
        else {
            return nil
        }

        return TokenUsageEvent(
            timestamp: timestamp,
            model: line.message?.model ?? "",
            inputTokens: usage.inputTokens ?? 0,
            outputTokens: usage.outputTokens ?? 0,
            cacheReadTokens: usage.cacheReadInputTokens ?? 0,
            cacheCreationTokens: usage.cacheCreationInputTokens ?? 0,
            sessionID: file.deletingPathExtension().lastPathComponent,
            projectDir: file.deletingLastPathComponent().lastPathComponent
        )
    }

    private struct LogLine: Decodable {
        let timestamp: String?
        let message: Message?

        struct Message: Decodable {
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

    private func jsonlFiles() -> [URL]? {
        guard fileManager.fileExists(atPath: rootURL.path) else { return nil }
        guard let enumerator = fileManager.enumerator(at: rootURL, includingPropertiesForKeys: nil) else {
            return []
        }
        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
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
