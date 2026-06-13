import Foundation
import os

/// Reads Gemini CLI usage from its opt-in local OpenTelemetry outfile (ADR-009).
///
/// Unlike Claude/Codex, Gemini CLI has no always-on per-turn usage log; its reliable
/// token source is the OpenTelemetry file exporter the CLI runs when telemetry is
/// enabled with `telemetry.target = local`. The exporter writes newline-delimited OTLP
/// JSON (one collector batch per line); token usage lives in log records whose
/// `event.name` attribute is `gemini_cli.api_response`, carrying `input_token_count`,
/// `output_token_count`, `cached_content_token_count`, `thoughts_token_count`,
/// `tool_token_count`, plus `model` and `session.id`.
///
/// The outfile path is auto-discovered from `~/.gemini/settings.json`
/// (`telemetry.outfile`), falling back to a default; a missing/undecodable settings file
/// uses the default, and a missing outfile yields an empty stream so the provider reads
/// as idle when telemetry is off (ADR-010).
///
/// Defensive by design, mirroring the Claude/Codex readers: the outfile is a single
/// file tracked by byte offset, only newly appended complete lines are parsed, the first
/// sight backfills only the retention tail, undecodable lines and records missing token
/// fields are skipped, and a file shorter than the stored offset is treated as rotated
/// and re-read from zero.
final class GeminiCLILogReader: TokenUsageReading {
    private let settingsURL: URL
    private let defaultOutfileURL: URL
    private let retentionTail: TimeInterval
    private let maxBackfillBytes: UInt64
    private let fileManager: FileManager
    private let now: () -> Date

    /// Byte offset into the currently-resolved outfile; `nil` before the file is first
    /// seen (or after the resolved path changes), which triggers a bounded backfill.
    private var offset: UInt64?
    /// The path the offset belongs to; a change re-seeds via backfill so a new outfile is
    /// never read from a stale offset.
    private var resolvedPath: String?

    private var didWarnMissingOutfile = false

    private static let newline: UInt8 = 0x0A
    private static let logger = Logger(subsystem: "MacMetricsView", category: "GeminiCLILogReader")

    init(
        settingsURL: URL = GeminiCLILogReader.defaultSettingsURL,
        defaultOutfileURL: URL = GeminiCLILogReader.defaultOutfileURL,
        retentionTail: TimeInterval = 24 * 60 * 60,
        maxBackfillBytes: UInt64 = 1 * 1024 * 1024,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = { Date() }
    ) {
        self.settingsURL = settingsURL
        self.defaultOutfileURL = defaultOutfileURL
        self.retentionTail = retentionTail
        self.maxBackfillBytes = maxBackfillBytes
        self.fileManager = fileManager
        self.now = now
    }

    static var defaultSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/settings.json", isDirectory: false)
    }

    /// Best-effort fallback when `settings.json` does not name an outfile. Discovery from
    /// settings is the primary path (ADR-010); this only matters when telemetry is
    /// configured to a non-standard location the settings file does not record.
    static var defaultOutfileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/otel.log", isDirectory: false)
    }

    func readNewEvents() -> [TokenUsageEvent] {
        let outfile = resolveOutfileURL()

        // Reset bookkeeping when the discovered path changes, so a new outfile is read
        // from a fresh backfill rather than a stale offset.
        if resolvedPath != outfile.path {
            resolvedPath = outfile.path
            offset = nil
        }

        guard fileManager.fileExists(atPath: outfile.path) else {
            if !didWarnMissingOutfile {
                didWarnMissingOutfile = true
                Self.logger.debug("Gemini telemetry outfile absent at \(outfile.path, privacy: .public)")
            }
            return []
        }
        didWarnMissingOutfile = false

        guard let size = fileSize(of: outfile) else { return [] }
        return readEvents(from: outfile, size: size)
    }

    // MARK: - Outfile discovery (ADR-010)

    /// Resolves the outfile path from `~/.gemini/settings.json` (`telemetry.outfile`),
    /// expanding a leading `~`; falls back to the default on a missing/undecodable file
    /// or absent key.
    private func resolveOutfileURL() -> URL {
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = try? Self.decoder.decode(GeminiSettings.self, from: data),
              let outfile = settings.telemetry?.outfile,
              !outfile.isEmpty
        else {
            return defaultOutfileURL
        }
        let expanded = (outfile as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
    }

    // MARK: - Per-file reading

    private func readEvents(from file: URL, size: UInt64) -> [TokenUsageEvent] {
        guard let entry = offset else {
            return backfill(file: file, size: size)
        }
        if size < entry { return backfill(file: file, size: size) }   // rotated / truncated
        if size == entry { return [] }                                // nothing appended

        guard let data = readData(from: file, start: entry) else { return [] }
        let parsed = parse(data, dropFirstPartial: false, applyTail: false)
        offset = entry + UInt64(parsed.consumed)
        return parsed.events
    }

    /// Seeds the offset to EOF and returns only events inside the retention tail, reading
    /// at most `maxBackfillBytes` from the end so cold start never ingests the full file.
    private func backfill(file: URL, size: UInt64) -> [TokenUsageEvent] {
        let start = size > maxBackfillBytes ? size - maxBackfillBytes : 0
        guard let data = readData(from: file, start: start) else {
            offset = size
            return []
        }
        let parsed = parse(data, dropFirstPartial: start > 0, applyTail: true)
        offset = start + UInt64(parsed.consumed)
        return parsed.events
    }

    // MARK: - Parsing

    /// Parses complete (newline-terminated) OTLP batch lines, flat-mapping each batch's
    /// `gemini_cli.api_response` records into events. Any trailing partial line is left
    /// unconsumed so it is re-read once fully written.
    private func parse(
        _ data: Data,
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
            for event in tokenEvents(from: Data(line)) {
                if applyTail, event.timestamp < cutoff { continue }
                events.append(event)
            }
        }
        return (events, consumable.count)
    }

    /// Decodes one OTLP batch line and returns an event for each `gemini_cli.api_response`
    /// log record. An undecodable line yields no events (skipped, never throws).
    private func tokenEvents(from data: Data) -> [TokenUsageEvent] {
        guard let batch = try? Self.decoder.decode(OTLPLogBatch.self, from: data) else { return [] }

        var events: [TokenUsageEvent] = []
        for resource in batch.resourceLogs ?? [] {
            for scope in resource.scopeLogs ?? [] {
                for record in scope.logRecords ?? [] {
                    if let event = tokenEvent(from: record) { events.append(event) }
                }
            }
        }
        return events
    }

    /// Maps a single `gemini_cli.api_response` record to a `TokenUsageEvent` (ADR-009/011).
    /// Returns `nil` for non-token records or records without a usable timestamp.
    private func tokenEvent(from record: OTLPLogBatch.LogRecord) -> TokenUsageEvent? {
        let attrs = AttributeMap(record.attributes)
        guard attrs.string("event.name") == "gemini_cli.api_response" else { return nil }
        guard let nanos = record.timeUnixNano.flatMap(Double.init) else { return nil }

        let timestamp = Date(timeIntervalSince1970: nanos / 1_000_000_000)

        // Tool tokens fold into input (ADR-011). Negative/absent counts clamp to 0 so a
        // malformed record can never drive a usage figure negative.
        let input = max(0, attrs.int("input_token_count")) + max(0, attrs.int("tool_token_count"))
        let output = max(0, attrs.int("output_token_count"))
        let cacheRead = max(0, attrs.int("cached_content_token_count"))
        let reasoning = max(0, attrs.int("thoughts_token_count"))

        return TokenUsageEvent(
            timestamp: timestamp,
            model: attrs.string("model") ?? "",
            inputTokens: input,
            outputTokens: output,
            cacheReadTokens: cacheRead,
            cacheCreationTokens: 0,           // Gemini reports no cache-creation category
            reasoningTokens: reasoning,
            sessionID: attrs.string("session.id") ?? "",
            projectDir: attrs.string("project.dir") ?? ""
        )
    }

    // MARK: - Decodable shapes

    private struct GeminiSettings: Decodable {
        let telemetry: Telemetry?
        struct Telemetry: Decodable { let outfile: String? }
    }

    /// Minimal slice of the OTLP logs export: only the fields Phase 5 consumes.
    private struct OTLPLogBatch: Decodable {
        let resourceLogs: [ResourceLogs]?
        struct ResourceLogs: Decodable { let scopeLogs: [ScopeLogs]? }
        struct ScopeLogs: Decodable { let logRecords: [LogRecord]? }
        struct LogRecord: Decodable {
            let timeUnixNano: String?
            let attributes: [KeyValue]?
        }
        struct KeyValue: Decodable {
            let key: String
            let value: AnyValue?
        }
        /// OTLP/JSON encodes attribute values as a typed wrapper; `intValue` is a string.
        struct AnyValue: Decodable {
            let stringValue: String?
            let intValue: String?
            let doubleValue: Double?
            let boolValue: Bool?
        }
    }

    /// Case-insensitive-free, key-exact attribute lookup over an OTLP attribute list.
    private struct AttributeMap {
        private let values: [String: OTLPLogBatch.AnyValue]

        init(_ attributes: [OTLPLogBatch.KeyValue]?) {
            var map: [String: OTLPLogBatch.AnyValue] = [:]
            for attr in attributes ?? [] where attr.value != nil {
                map[attr.key] = attr.value
            }
            values = map
        }

        func string(_ key: String) -> String? {
            values[key]?.stringValue
        }

        /// Reads an integer attribute. OTLP encodes `intValue` as a string; a numeric
        /// `doubleValue` is accepted as a fallback. Missing/non-numeric → 0.
        func int(_ key: String) -> Int {
            guard let value = values[key] else { return 0 }
            if let raw = value.intValue, let parsed = Int(raw) { return parsed }
            if let raw = value.doubleValue { return Int(raw) }
            return 0
        }
    }

    private static let decoder = JSONDecoder()

    // MARK: - Filesystem helpers

    private func fileSize(of file: URL) -> UInt64? {
        (try? fileManager.attributesOfItem(atPath: file.path)[.size]) as? UInt64
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
