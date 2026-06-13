import XCTest
@testable import MacMetricsView

/// Covers `GeminiCLILogReader` (task_04, ADR-009/010): outfile discovery from
/// `settings.json` with default fallback, OTLP/JSON NDJSON parsing of
/// `gemini_cli.api_response` records, the field map (incl. tool→input fold),
/// offset/rotation handling, retention-tail backfill, and defensive skipping of
/// malformed/incomplete records.
final class GeminiCLILogReaderTests: XCTestCase {

    private var dir: URL!
    /// `now` is just after the synthetic event epochs so the default 24h tail keeps them.
    private let fixedNow = Date(timeIntervalSince1970: 1_700_000_100)

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("geminireader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Fixture builders

    /// One OTLP batch line containing a single log record. Pass `eventName: nil` to omit
    /// the `event.name` attribute, `epoch: nil` to omit `timeUnixNano`.
    private func batchLine(
        model: String,
        input: Int,
        output: Int,
        cached: Int,
        thoughts: Int,
        tool: Int,
        session: String,
        epoch: Double?,
        eventName: String? = "gemini_cli.api_response"
    ) -> String {
        var attrs: [String] = []
        if let eventName {
            attrs.append(stringAttr("event.name", eventName))
        }
        attrs.append(stringAttr("model", model))
        attrs.append(intAttr("input_token_count", input))
        attrs.append(intAttr("output_token_count", output))
        attrs.append(intAttr("cached_content_token_count", cached))
        attrs.append(intAttr("thoughts_token_count", thoughts))
        attrs.append(intAttr("tool_token_count", tool))
        attrs.append(stringAttr("session.id", session))

        let timeField = epoch.map { #""timeUnixNano":"\#(Int64($0 * 1_000_000_000))","# } ?? ""
        let record = #"{\#(timeField)"attributes":[\#(attrs.joined(separator: ","))]}"#
        return #"{"resourceLogs":[{"scopeLogs":[{"logRecords":[\#(record)]}]}]}"#
    }

    private func stringAttr(_ key: String, _ value: String) -> String {
        #"{"key":"\#(key)","value":{"stringValue":"\#(value)"}}"#
    }

    private func intAttr(_ key: String, _ value: Int) -> String {
        #"{"key":"\#(key)","value":{"intValue":"\#(value)"}}"#
    }

    @discardableResult
    private func writeOutfile(_ lines: [String], name: String = "otel.log") throws -> URL {
        let url = dir.appendingPathComponent(name)
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func writeSettings(outfile: String) throws -> URL {
        let url = dir.appendingPathComponent("settings.json")
        try #"{"telemetry":{"enabled":true,"target":"local","outfile":"\#(outfile)"}}"#
            .write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeReader(settings: URL, defaultOutfile: URL) -> GeminiCLILogReader {
        GeminiCLILogReader(
            settingsURL: settings,
            defaultOutfileURL: defaultOutfile,
            now: { self.fixedNow }
        )
    }

    // MARK: - Discovery

    func testResolvesOutfileFromSettings() throws {
        let outfile = try writeOutfile([
            batchLine(model: "gemini-2.5-pro", input: 100, output: 20, cached: 0,
                      thoughts: 0, tool: 0, session: "s1", epoch: 1_700_000_000)
        ])
        let settings = try writeSettings(outfile: outfile.path)
        let reader = makeReader(settings: settings, defaultOutfile: dir.appendingPathComponent("nope.log"))

        let events = reader.readNewEvents()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.model, "gemini-2.5-pro")
    }

    func testFallsBackToDefaultWhenSettingsMissing() throws {
        let outfile = try writeOutfile([
            batchLine(model: "gemini-2.5-flash", input: 10, output: 5, cached: 0,
                      thoughts: 0, tool: 0, session: "s1", epoch: 1_700_000_000)
        ])
        let missingSettings = dir.appendingPathComponent("absent-settings.json")
        let reader = makeReader(settings: missingSettings, defaultOutfile: outfile)

        XCTAssertEqual(reader.readNewEvents().count, 1)
    }

    func testAbsentOutfileReturnsEmpty() throws {
        let missingSettings = dir.appendingPathComponent("absent-settings.json")
        let missingOutfile = dir.appendingPathComponent("absent-otel.log")
        let reader = makeReader(settings: missingSettings, defaultOutfile: missingOutfile)

        XCTAssertEqual(reader.readNewEvents(), [])
    }

    // MARK: - Field map

    func testParsesRecordsAcrossModelsWithFieldMap() throws {
        let outfile = try writeOutfile([
            batchLine(model: "gemini-2.5-pro", input: 1200, output: 340, cached: 800,
                      thoughts: 50, tool: 0, session: "sess-aaa", epoch: 1_700_000_000),
            batchLine(model: "gemini-2.5-flash", input: 500, output: 120, cached: 0,
                      thoughts: 0, tool: 10, session: "sess-bbb", epoch: 1_700_000_060)
        ])
        let reader = makeReader(settings: dir.appendingPathComponent("none.json"), defaultOutfile: outfile)

        let events = reader.readNewEvents()
        XCTAssertEqual(events.count, 2)

        let pro = try XCTUnwrap(events.first { $0.model == "gemini-2.5-pro" })
        XCTAssertEqual(pro.inputTokens, 1200)      // tool 0 → input unchanged
        XCTAssertEqual(pro.outputTokens, 340)
        XCTAssertEqual(pro.cacheReadTokens, 800)
        XCTAssertEqual(pro.reasoningTokens, 50)    // thoughts → reasoning
        XCTAssertEqual(pro.cacheCreationTokens, 0)
        XCTAssertEqual(pro.sessionID, "sess-aaa")
        XCTAssertEqual(pro.timestamp, Date(timeIntervalSince1970: 1_700_000_000))

        let flash = try XCTUnwrap(events.first { $0.model == "gemini-2.5-flash" })
        XCTAssertEqual(flash.inputTokens, 510)     // 500 input + 10 tool (ADR-011)
    }

    // MARK: - Defensive parsing

    func testMalformedLineSkippedSurroundingValid() throws {
        let valid = batchLine(model: "gemini-2.5-pro", input: 100, output: 20, cached: 0,
                              thoughts: 0, tool: 0, session: "s1", epoch: 1_700_000_000)
        let outfile = try writeOutfile([valid, "{ this is not json", valid])
        let reader = makeReader(settings: dir.appendingPathComponent("none.json"), defaultOutfile: outfile)

        XCTAssertEqual(reader.readNewEvents().count, 2)
    }

    func testRecordMissingEventNameSkipped() throws {
        let outfile = try writeOutfile([
            batchLine(model: "gemini-2.5-pro", input: 100, output: 20, cached: 0,
                      thoughts: 0, tool: 0, session: "s1", epoch: 1_700_000_000, eventName: nil)
        ])
        let reader = makeReader(settings: dir.appendingPathComponent("none.json"), defaultOutfile: outfile)

        XCTAssertEqual(reader.readNewEvents(), [])
    }

    func testRecordMissingTimestampSkipped() throws {
        let outfile = try writeOutfile([
            batchLine(model: "gemini-2.5-pro", input: 100, output: 20, cached: 0,
                      thoughts: 0, tool: 0, session: "s1", epoch: nil)
        ])
        let reader = makeReader(settings: dir.appendingPathComponent("none.json"), defaultOutfile: outfile)

        XCTAssertEqual(reader.readNewEvents(), [])
    }

    // MARK: - Incremental read / rotation

    func testIncrementalReadReturnsOnlyNewEvents() throws {
        let outfile = dir.appendingPathComponent("otel.log")
        let first = batchLine(model: "gemini-2.5-pro", input: 100, output: 20, cached: 0,
                              thoughts: 0, tool: 0, session: "s1", epoch: 1_700_000_000)
        try (first + "\n").write(to: outfile, atomically: true, encoding: .utf8)

        let reader = makeReader(settings: dir.appendingPathComponent("none.json"), defaultOutfile: outfile)
        XCTAssertEqual(reader.readNewEvents().count, 1)

        // Append a second batch; only the new event should come back.
        let second = batchLine(model: "gemini-2.5-flash", input: 50, output: 10, cached: 0,
                              thoughts: 0, tool: 0, session: "s2", epoch: 1_700_000_060)
        let handle = try FileHandle(forWritingTo: outfile)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((second + "\n").utf8))
        try handle.close()

        let next = reader.readNewEvents()
        XCTAssertEqual(next.count, 1)
        XCTAssertEqual(next.first?.model, "gemini-2.5-flash")
    }

    func testShorterFileReReadsFromZero() throws {
        let outfile = dir.appendingPathComponent("otel.log")
        let a = batchLine(model: "gemini-2.5-pro", input: 100, output: 20, cached: 0,
                          thoughts: 0, tool: 0, session: "s1", epoch: 1_700_000_000)
        let b = batchLine(model: "gemini-2.5-flash", input: 50, output: 10, cached: 0,
                          thoughts: 0, tool: 0, session: "s2", epoch: 1_700_000_010)
        try ([a, b].joined(separator: "\n") + "\n").write(to: outfile, atomically: true, encoding: .utf8)

        let reader = makeReader(settings: dir.appendingPathComponent("none.json"), defaultOutfile: outfile)
        XCTAssertEqual(reader.readNewEvents().count, 2)

        // Truncate to a single, different record → treated as rotated, re-read from zero.
        let c = batchLine(model: "gemini-2.5-pro", input: 7, output: 3, cached: 0,
                          thoughts: 0, tool: 0, session: "s3", epoch: 1_700_000_020)
        try (c + "\n").write(to: outfile, atomically: true, encoding: .utf8)

        let after = reader.readNewEvents()
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(after.first?.sessionID, "s3")
    }

    func testBackfillExcludesEventsBeyondRetentionTail() throws {
        // One event 25h before `now` (beyond the 24h tail) and one recent.
        let oldEpoch = fixedNow.addingTimeInterval(-25 * 3_600).timeIntervalSince1970
        let outfile = try writeOutfile([
            batchLine(model: "gemini-2.5-pro", input: 100, output: 20, cached: 0,
                      thoughts: 0, tool: 0, session: "old", epoch: oldEpoch),
            batchLine(model: "gemini-2.5-flash", input: 50, output: 10, cached: 0,
                      thoughts: 0, tool: 0, session: "new", epoch: 1_700_000_060)
        ])
        let reader = makeReader(settings: dir.appendingPathComponent("none.json"), defaultOutfile: outfile)

        let events = reader.readNewEvents()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.sessionID, "new")
    }

    // MARK: - Committed fixture (task_01 ↔ task_04 bridge)

    func testCommittedFixtureParses() throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/gemini/otel.log")
        let reader = makeReader(settings: dir.appendingPathComponent("none.json"), defaultOutfile: fixture)

        let events = reader.readNewEvents()
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(Set(events.map(\.model)), ["gemini-2.5-pro", "gemini-2.5-flash"])
        // gemini-2.5-flash fixture carries tool_token_count 10 folded into input 500.
        XCTAssertEqual(events.first { $0.model == "gemini-2.5-flash" }?.inputTokens, 510)
    }
}
