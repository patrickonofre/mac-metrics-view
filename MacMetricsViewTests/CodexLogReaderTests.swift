import XCTest
@testable import MacMetricsView

/// Covers `CodexLogReader` parsing of real-shaped rollout JSONL (task_03, ADR-004):
/// per-turn `last_token_usage` with the non-overlapping mapping, dedupe of the
/// double-emitted `token_count` events via the cumulative gate, offset/rotation handling,
/// and defensive skipping of malformed/tokenless lines.
final class CodexLogReaderTests: XCTestCase {

    private var root: URL!
    private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
    /// Mutable clock for reactivation tests that advance `now` past the active window.
    private var currentNow = Date(timeIntervalSince1970: 1_700_000_000)
    private let uuid = "019c8cc1-a150-7be1-977b-3ba98fe3fe2e"

    /// Codex date dirs are local-time; pin the reader and the fixtures to UTC so the computed
    /// `YYYY/MM/DD` directory is deterministic regardless of the host timezone.
    private static let utc = TimeZone(identifier: "UTC")!

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar
    }()

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexreader-\(UUID().uuidString)/sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    // MARK: - Fixture helpers

    /// `root/YYYY/MM/DD` for `base` shifted by `dayOffset`, computed in UTC to match the
    /// reader's date-dir resolver under the injected UTC timezone.
    private func dateDir(base: Date? = nil, dayOffset: Int = 0) -> URL {
        let day = Self.utcCalendar.date(byAdding: .day, value: dayOffset, to: base ?? fixedNow)!
        let parts = Self.utcCalendar.dateComponents([.year, .month, .day], from: day)
        return root
            .appendingPathComponent(String(format: "%04d", parts.year!), isDirectory: true)
            .appendingPathComponent(String(format: "%02d", parts.month!), isDirectory: true)
            .appendingPathComponent(String(format: "%02d", parts.day!), isDirectory: true)
    }

    private func rolloutFile(uuid: String? = nil, base: Date? = nil, dayOffset: Int = 0) throws -> URL {
        let day = dateDir(base: base, dayOffset: dayOffset)
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        let id = uuid ?? self.uuid
        return day.appendingPathComponent("rollout-session-\(id).jsonl")
    }

    private func sessionMeta(cwd: String, at offset: TimeInterval = -3_600) -> String {
        let ts = Self.iso.string(from: fixedNow.addingTimeInterval(offset))
        return #"{"timestamp":"\#(ts)","type":"session_meta","payload":{"id":"\#(uuid)","cwd":"\#(cwd)","model_provider":"openai"}}"#
    }

    private func turnContext(model: String, cwd: String? = nil, at offset: TimeInterval = -3_600) -> String {
        let ts = Self.iso.string(from: fixedNow.addingTimeInterval(offset))
        let cwdField = cwd.map { #","cwd":"\#($0)""# } ?? ""
        return #"{"timestamp":"\#(ts)","type":"turn_context","payload":{"model":"\#(model)"\#(cwdField)}}"#
    }

    /// A `token_count` event_msg line. Codex logs each turn's event twice, so callers
    /// usually emit this with the same cumulative twice.
    private func tokenLine(
        at offset: TimeInterval,
        cumInput: Int, cumCached: Int, cumOutput: Int, cumReasoning: Int, cumTotal: Int,
        lastInput: Int, lastCached: Int, lastOutput: Int, lastReasoning: Int, lastTotal: Int
    ) -> String {
        let ts = Self.iso.string(from: fixedNow.addingTimeInterval(offset))
        func usage(_ i: Int, _ c: Int, _ o: Int, _ r: Int, _ t: Int) -> String {
            #"{"input_tokens":\#(i),"cached_input_tokens":\#(c),"output_tokens":\#(o),"reasoning_output_tokens":\#(r),"total_tokens":\#(t)}"#
        }
        let total = usage(cumInput, cumCached, cumOutput, cumReasoning, cumTotal)
        let last = usage(lastInput, lastCached, lastOutput, lastReasoning, lastTotal)
        return #"{"timestamp":"\#(ts)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":\#(total),"last_token_usage":\#(last)}}}"#
    }

    /// Builds the duplicate-emitted token lines for a chain of turns, accumulating the
    /// cumulative totals exactly as Codex does (total_tokens = input + output).
    private func turnLines(
        _ turns: [(offset: TimeInterval, input: Int, cached: Int, output: Int, reasoning: Int)]
    ) -> [String] {
        var ci = 0, cc = 0, co = 0, cr = 0, ct = 0
        var lines: [String] = []
        for t in turns {
            let lastTotal = t.input + t.output
            ci += t.input; cc += t.cached; co += t.output; cr += t.reasoning; ct += lastTotal
            let line = tokenLine(
                at: t.offset,
                cumInput: ci, cumCached: cc, cumOutput: co, cumReasoning: cr, cumTotal: ct,
                lastInput: t.input, lastCached: t.cached, lastOutput: t.output,
                lastReasoning: t.reasoning, lastTotal: lastTotal
            )
            lines.append(line)
            lines.append(line)   // Codex emits each turn's token_count twice
        }
        return lines
    }

    private func write(_ lines: [String], to file: URL) throws {
        try (lines.joined(separator: "\n") + "\n").data(using: .utf8)!.write(to: file)
    }

    private func append(_ lines: [String], to file: URL) throws {
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: (lines.joined(separator: "\n") + "\n").data(using: .utf8)!)
    }

    private func makeReader(root: URL? = nil) -> CodexLogReader {
        CodexLogReader(rootURL: root ?? self.root, timeZone: Self.utc, now: { self.fixedNow })
    }

    /// Reader bound to the mutable `currentNow` clock (reactivation tests).
    private func makeMutableReader() -> CodexLogReader {
        CodexLogReader(rootURL: root, timeZone: Self.utc, now: { self.currentNow })
    }

    private func setMtime(_ file: URL, offsetFrom base: Date, _ offset: TimeInterval) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: base.addingTimeInterval(offset)],
            ofItemAtPath: file.path
        )
    }

    // MARK: - Mapping & reconciliation

    func testRealShapedTurnReconcilesToTotalTokens() throws {
        let file = try rolloutFile()
        try write(
            [sessionMeta(cwd: "/proj"), turnContext(model: "gpt-5.3-codex")]
            + turnLines([(offset: -60, input: 23_260, cached: 7_552, output: 1_060, reasoning: 689)]),
            to: file
        )

        let events = makeReader().readNewEvents()

        XCTAssertEqual(events.count, 1)   // double-emitted line counted once
        let e = try XCTUnwrap(events.first)
        XCTAssertEqual(e.inputTokens, 15_708)        // 23260 - 7552
        XCTAssertEqual(e.outputTokens, 371)          // 1060 - 689
        XCTAssertEqual(e.cacheReadTokens, 7_552)
        XCTAssertEqual(e.cacheCreationTokens, 0)
        XCTAssertEqual(e.reasoningTokens, 689)
        XCTAssertEqual(TokenAggregate.zero.adding(e).total, 24_320)   // reconciles to total_tokens
    }

    func testUsesPerTurnLastNotCumulative() throws {
        let file = try rolloutFile()
        try write(
            [sessionMeta(cwd: "/proj"), turnContext(model: "gpt-5.3-codex")]
            + turnLines([
                (offset: -120, input: 23_260, cached: 7_552, output: 1_060, reasoning: 689),  // last total 24320
                (offset: -60, input: 10_000, cached: 0, output: 1_565, reasoning: 0)           // last total 11565
            ]),
            to: file
        )

        let events = makeReader().readNewEvents()

        XCTAssertEqual(events.count, 2)   // 4 lines (two dup pairs) → 2 turns
        // Per-turn deltas, NOT the cumulative 24320 / 35885.
        XCTAssertEqual(events.map { TokenAggregate.zero.adding($0).total }, [24_320, 11_565])
    }

    func testSubtractionClampsAtZeroOnAdversarialFields() throws {
        let file = try rolloutFile()
        // cached > input and reasoning > output → mapped input/output must clamp at 0.
        try write(
            [sessionMeta(cwd: "/proj"), turnContext(model: "gpt-5-codex")]
            + turnLines([(offset: -60, input: 50, cached: 100, output: 60, reasoning: 80)]),
            to: file
        )

        let e = try XCTUnwrap(makeReader().readNewEvents().first)
        XCTAssertEqual(e.inputTokens, 0)      // max(0, 50 - 100)
        XCTAssertEqual(e.outputTokens, 0)     // max(0, 60 - 80)
        XCTAssertEqual(e.cacheReadTokens, 100)
        XCTAssertEqual(e.reasoningTokens, 80)
    }

    // MARK: - Context attachment

    func testCwdModelAndSessionIDAttached() throws {
        let file = try rolloutFile()
        try write(
            [sessionMeta(cwd: "/Users/x/myproj"), turnContext(model: "gpt-5-codex")]
            + turnLines([(offset: -60, input: 100, cached: 0, output: 50, reasoning: 0)]),
            to: file
        )

        let e = try XCTUnwrap(makeReader().readNewEvents().first)
        XCTAssertEqual(e.projectDir, "/Users/x/myproj")
        XCTAssertEqual(e.model, "gpt-5-codex")
        XCTAssertEqual(e.sessionID, uuid)
    }

    func testCwdFallsBackToTurnContextWhenSessionMetaMissing() throws {
        let file = try rolloutFile()
        // No session_meta in the read window; turn_context carries cwd as a fallback.
        try write(
            [turnContext(model: "gpt-5-codex", cwd: "/from/turn")]
            + turnLines([(offset: -60, input: 100, cached: 0, output: 50, reasoning: 0)]),
            to: file
        )

        let e = try XCTUnwrap(makeReader().readNewEvents().first)
        XCTAssertEqual(e.projectDir, "/from/turn")
    }

    // MARK: - Resilience

    func testMalformedAndTokenlessLinesSkipped() throws {
        let file = try rolloutFile()
        let rateLimitOnly = #"{"timestamp":"\#(Self.iso.string(from: fixedNow))","type":"event_msg","payload":{"type":"token_count","info":null}}"#
        try write(
            [
                sessionMeta(cwd: "/proj"),
                turnContext(model: "gpt-5-codex"),
                "{ not valid json",
                rateLimitOnly,
                #"{"timestamp":"x","type":"response_item","payload":{"foo":"bar"}}"#
            ]
            + turnLines([(offset: -60, input: 100, cached: 0, output: 50, reasoning: 0)]),
            to: file
        )

        let events = makeReader().readNewEvents()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.inputTokens, 100)
    }

    func testSecondReadReturnsOnlyNewTurns() throws {
        let file = try rolloutFile()
        try write(
            [sessionMeta(cwd: "/proj"), turnContext(model: "gpt-5-codex")]
            + turnLines([(offset: -120, input: 100, cached: 0, output: 50, reasoning: 0)]),
            to: file
        )
        let reader = makeReader()
        XCTAssertEqual(reader.readNewEvents().count, 1)

        // Append a second turn (continuing the cumulative chain) emitted twice.
        try append(
            [tokenLine(
                at: -60,
                cumInput: 300, cumCached: 0, cumOutput: 120, cumReasoning: 0, cumTotal: 420,
                lastInput: 200, lastCached: 0, lastOutput: 70, lastReasoning: 0, lastTotal: 270
            ),
             tokenLine(
                at: -60,
                cumInput: 300, cumCached: 0, cumOutput: 120, cumReasoning: 0, cumTotal: 420,
                lastInput: 200, lastCached: 0, lastOutput: 70, lastReasoning: 0, lastTotal: 270
            )],
            to: file
        )

        let second = reader.readNewEvents()
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second.first?.inputTokens, 200)
        XCTAssertEqual(reader.readNewEvents(), [])   // nothing new
    }

    func testFileTruncatedBelowOffsetIsReReadFromZero() throws {
        let file = try rolloutFile()
        try write(
            [sessionMeta(cwd: "/proj"), turnContext(model: "gpt-5-codex")]
            + turnLines([
                (offset: -120, input: 100, cached: 0, output: 50, reasoning: 0),
                (offset: -110, input: 200, cached: 0, output: 60, reasoning: 0)
            ]),
            to: file
        )
        let reader = makeReader()
        _ = reader.readNewEvents()

        // Rotation: a shorter new session file at the same path.
        try write(
            [sessionMeta(cwd: "/proj2"), turnContext(model: "gpt-5-codex")]
            + turnLines([(offset: -10, input: 7, cached: 0, output: 3, reasoning: 0)]),
            to: file
        )

        let events = reader.readNewEvents()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.inputTokens, 7)
        XCTAssertEqual(events.first?.projectDir, "/proj2")
    }

    func testFirstPassBackfillsOnlyRetentionTail() throws {
        let file = try rolloutFile()
        try write(
            [sessionMeta(cwd: "/proj"), turnContext(model: "gpt-5-codex")]
            + turnLines([
                (offset: -48 * 3_600, input: 999, cached: 0, output: 1, reasoning: 0),  // 48h ago, outside tail
                (offset: -1 * 3_600, input: 42, cached: 0, output: 8, reasoning: 0)      // 1h ago, inside tail
            ]),
            to: file
        )

        let events = makeReader().readNewEvents()
        XCTAssertEqual(events.map(\.inputTokens), [42])
    }

    func testMissingRootReturnsEmpty() {
        let reader = CodexLogReader(
            rootURL: root.appendingPathComponent("does-not-exist", isDirectory: true),
            now: { self.fixedNow }
        )
        XCTAssertEqual(reader.readNewEvents(), [])
    }

    func testArchivedSessionsAreNotScanned() throws {
        // Sibling archived dir under ~/.codex, never enumerated because root is sessions/.
        let archived = root.deletingLastPathComponent()
            .appendingPathComponent("archived_sessions/2026/02/23", isDirectory: true)
        try FileManager.default.createDirectory(at: archived, withIntermediateDirectories: true)
        let archivedFile = archived.appendingPathComponent("rollout-2026-02-23T20-07-05-\(uuid).jsonl")
        try write(
            [sessionMeta(cwd: "/proj"), turnContext(model: "gpt-5-codex")]
            + turnLines([(offset: -60, input: 5_000, cached: 0, output: 100, reasoning: 0)]),
            to: archivedFile
        )

        // Active sessions dir is empty → nothing counted.
        XCTAssertEqual(makeReader().readNewEvents(), [])
    }

    // MARK: - Date-dir scoping & reactivation (task_03)

    func testFileUnderOldDateDirNotWalked() throws {
        // 10 days before `now` → outside the window + margin date dirs, even though the file's
        // mtime is recent: it is the *scoping* (not the mtime) that excludes it.
        let old = try rolloutFile(dayOffset: -10)
        try write(
            [sessionMeta(cwd: "/proj"), turnContext(model: "gpt-5-codex")]
            + turnLines([(offset: -60, input: 5_000, cached: 0, output: 100, reasoning: 0)]),
            to: old
        )
        try setMtime(old, offsetFrom: fixedNow, -60)

        XCTAssertEqual(makeReader().readNewEvents(), [])
    }

    func testFileNearMidnightInPreviousDateDirIncludedViaMargin() throws {
        // Previous date dir, mtime still inside the active window → included via the margin.
        let file = try rolloutFile(dayOffset: -1)
        try write(
            [sessionMeta(cwd: "/proj"), turnContext(model: "gpt-5-codex")]
            + turnLines([(offset: -60, input: 100, cached: 0, output: 50, reasoning: 0)]),
            to: file
        )
        try setMtime(file, offsetFrom: fixedNow, -3_600)

        let events = makeReader().readNewEvents()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.inputTokens, 100)
    }

    func testReactivationAfterEvictionEmitsOnlyNewTurn() throws {
        let file = try rolloutFile()   // under today's (fixedNow) date dir
        try write(
            [sessionMeta(cwd: "/proj"), turnContext(model: "gpt-5-codex")]
            + turnLines([(offset: -60, input: 100, cached: 0, output: 50, reasoning: 0)]),
            to: file
        )
        try setMtime(file, offsetFrom: fixedNow, -60)
        let reader = makeMutableReader()
        XCTAssertEqual(reader.readNewEvents().count, 1)

        // Advance well past the window: the file's state is evicted on the next pass.
        currentNow = fixedNow.addingTimeInterval(48 * 3_600)
        XCTAssertEqual(reader.readNewEvents(), [])

        // A genuinely new turn arrives, timestamped in-tail vs currentNow (offset off fixedNow).
        try append(
            turnLines([(offset: 48 * 3_600 - 60, input: 200, cached: 0, output: 70, reasoning: 0)]),
            to: file
        )
        try setMtime(file, offsetFrom: currentNow, -30)

        let reactivated = reader.readNewEvents()
        // Only the new turn emits; the pre-eviction turn is tail-filtered, never re-counted.
        XCTAssertEqual(reactivated.count, 1)
        XCTAssertEqual(reactivated.first?.inputTokens, 200)
        XCTAssertEqual(reactivated.first?.projectDir, "/proj")   // cwd re-read from the header
        XCTAssertEqual(reader.readNewEvents(), [])
    }

    func testFiguresIdenticalMultiDayCorpus() throws {
        let otherUUID = "019c8cc1-a150-7be1-977b-3ba98fe3fe2f"
        let today = try rolloutFile(uuid: uuid, dayOffset: 0)
        let yesterday = try rolloutFile(uuid: otherUUID, dayOffset: -1)
        try write(
            [sessionMeta(cwd: "/a"), turnContext(model: "gpt-5-codex")]
            + turnLines([(offset: -60, input: 100, cached: 0, output: 50, reasoning: 0)]),
            to: today
        )
        try write(
            [sessionMeta(cwd: "/b"), turnContext(model: "gpt-5-codex")]
            + turnLines([(offset: -120, input: 200, cached: 0, output: 60, reasoning: 0)]),
            to: yesterday
        )

        let events = makeReader().readNewEvents()

        // Order across date dirs is filesystem-dependent; assert the multiset and totals.
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.map(\.inputTokens).sorted(), [100, 200])
        XCTAssertEqual(events.reduce(0) { $0 + $1.outputTokens }, 110)
    }
}
