import XCTest
@testable import MacMetricsView

/// Validation gate for the constant-cost token reading initiative (task_04, ADR-001/002/003).
///
/// Proves the two PRD success metrics with a synthetic corpus:
/// - **Cost independence** — per-cycle read work (emitted events + tracked-file count) for a
///   small active set is the same whether the corpus has ~10 or thousands of dormant files.
/// - **Memory ceiling** — `ActiveFileSet.entries` (and the readers' `activeFileCount`) plateau
///   across a simulated multi-day `now` progression, never trending up with corpus or uptime.
final class ReaderBenchmarkTests: XCTestCase {

    private var root: URL!
    private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
    private let window: TimeInterval = 24 * 60 * 60

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
            .appendingPathComponent("bench-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Fixture generators

    private func setMtime(_ url: URL, _ date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    @discardableResult
    private func makeClaudeFile(name: String, tsBase: Date, mtime: Date, input: Int, in dir: URL) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(name).jsonl")
        let ts = Self.iso.string(from: tsBase.addingTimeInterval(-60))
        let line = #"{"timestamp":"\#(ts)","message":{"id":"\#(name)","model":"m","usage":{"input_tokens":\#(input),"output_tokens":1}}}"#
        try (line + "\n").data(using: .utf8)!.write(to: file)
        try setMtime(file, mtime)
        return file
    }

    /// Builds `active` files (recent mtime) + `dormant` files (mtime one window+ old) under a
    /// Claude-style root. Returns the active file URLs.
    @discardableResult
    private func makeClaudeCorpus(root: URL, active: Int, dormant: Int, tsBase: Date, tag: String = "") throws -> [URL] {
        var actives: [URL] = []
        for i in 0..<active {
            actives.append(try makeClaudeFile(
                name: "active-\(tag)\(i)", tsBase: tsBase, mtime: tsBase.addingTimeInterval(-60),
                input: 100 + i, in: root.appendingPathComponent("pa-\(tag)\(i)", isDirectory: true)
            ))
        }
        for i in 0..<dormant {
            try makeClaudeFile(
                name: "dormant-\(tag)\(i)", tsBase: tsBase, mtime: tsBase.addingTimeInterval(-window - 3_600),
                input: 9, in: root.appendingPathComponent("pd-\(tag)\(i)", isDirectory: true)
            )
        }
        return actives
    }

    private func codexDateDir(under root: URL, for date: Date) -> URL {
        let parts = Self.utcCalendar.dateComponents([.year, .month, .day], from: date)
        return root
            .appendingPathComponent(String(format: "%04d", parts.year!), isDirectory: true)
            .appendingPathComponent(String(format: "%02d", parts.month!), isDirectory: true)
            .appendingPathComponent(String(format: "%02d", parts.day!), isDirectory: true)
    }

    @discardableResult
    private func makeCodexFile(name: String, tsBase: Date, mtime: Date, input: Int, in dir: URL) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("rollout-\(name).jsonl")
        let ts = Self.iso.string(from: tsBase.addingTimeInterval(-60))
        let meta = #"{"timestamp":"\#(ts)","type":"session_meta","payload":{"cwd":"/p","model_provider":"openai"}}"#
        let ctx = #"{"timestamp":"\#(ts)","type":"turn_context","payload":{"model":"gpt-5-codex"}}"#
        let total = #"{"input_tokens":\#(input),"cached_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0,"total_tokens":\#(input + 1)}"#
        let token = #"{"timestamp":"\#(ts)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":\#(total),"last_token_usage":\#(total)}}}"#
        try ([meta, ctx, token].joined(separator: "\n") + "\n").data(using: .utf8)!.write(to: file)
        try setMtime(file, mtime)
        return file
    }

    /// Active + dormant rollout files all under the same recent date dir (so date-dir scoping
    /// includes them and the mtime active-window is what excludes the dormant ones).
    @discardableResult
    private func makeCodexCorpus(root: URL, active: Int, dormant: Int, tsBase: Date, tag: String = "") throws -> [URL] {
        let dir = codexDateDir(under: root, for: tsBase)
        var actives: [URL] = []
        for i in 0..<active {
            actives.append(try makeCodexFile(
                name: "a-\(tag)\(i)-019c8cc1-a150-7be1-977b-3ba98fe3fe2e", tsBase: tsBase,
                mtime: tsBase.addingTimeInterval(-60), input: 100 + i, in: dir
            ))
        }
        for i in 0..<dormant {
            try makeCodexFile(
                name: "d-\(tag)\(i)-019c8cc1-a150-7be1-977b-3ba98fe3fe2e", tsBase: tsBase,
                mtime: tsBase.addingTimeInterval(-window - 3_600), input: 9, in: dir
            )
        }
        return actives
    }

    // MARK: - 4.1 Fixture generator sanity

    func testFixtureGeneratorProducesControllableActiveAndDormantCounts() throws {
        let claudeRoot = root.appendingPathComponent("claude", isDirectory: true)
        try makeClaudeCorpus(root: claudeRoot, active: 2, dormant: 5, tsBase: fixedNow)

        var set = ActiveFileSet<Int>()
        let active = set.activeFiles(
            roots: [claudeRoot], window: window, now: fixedNow, fileManager: .default,
            matches: { $0.pathExtension == "jsonl" }
        )
        XCTAssertEqual(active.count, 2, "only the 2 recent-mtime files are active among 7 total")
    }

    // MARK: - Cost independence

    func testClaudeReadWorkIndependentOfCorpusSize() throws {
        let small = root.appendingPathComponent("c-small", isDirectory: true)
        let big = root.appendingPathComponent("c-big", isDirectory: true)
        try makeClaudeCorpus(root: small, active: 1, dormant: 10, tsBase: fixedNow)
        try makeClaudeCorpus(root: big, active: 1, dormant: 2_000, tsBase: fixedNow)

        let rSmall = ClaudeCodeLogReader(rootURL: small, now: { self.fixedNow })
        let rBig = ClaudeCodeLogReader(rootURL: big, now: { self.fixedNow })
        let eSmall = rSmall.readNewEvents()
        let eBig = rBig.readNewEvents()

        XCTAssertEqual(eSmall.count, 1)
        XCTAssertEqual(eBig.count, 1)
        // Tracked state + emitted figures depend on the active set, not 10 vs 2000 dormant.
        XCTAssertEqual(rSmall.activeFileCount, 1)
        XCTAssertEqual(rBig.activeFileCount, 1)
        XCTAssertEqual(eSmall.map(\.inputTokens), eBig.map(\.inputTokens))
    }

    func testCodexReadWorkIndependentOfCorpusSize() throws {
        let small = root.appendingPathComponent("x-small/sessions", isDirectory: true)
        let big = root.appendingPathComponent("x-big/sessions", isDirectory: true)
        try makeCodexCorpus(root: small, active: 1, dormant: 10, tsBase: fixedNow)
        try makeCodexCorpus(root: big, active: 1, dormant: 2_000, tsBase: fixedNow)

        let rSmall = CodexLogReader(rootURL: small, timeZone: Self.utc, now: { self.fixedNow })
        let rBig = CodexLogReader(rootURL: big, timeZone: Self.utc, now: { self.fixedNow })
        let eSmall = rSmall.readNewEvents()
        let eBig = rBig.readNewEvents()

        XCTAssertEqual(eSmall.count, 1)
        XCTAssertEqual(eBig.count, 1)
        XCTAssertEqual(rSmall.activeFileCount, 1)
        XCTAssertEqual(rBig.activeFileCount, 1)
        XCTAssertEqual(eSmall.map(\.inputTokens), eBig.map(\.inputTokens))
    }

    // MARK: - Memory ceiling

    func testActiveFileSetEntriesPlateauAcrossMultiDayProgression() throws {
        // One always-dormant pile + a small set that turns over each "day". entries must track
        // only the current active set, never the cumulative file count.
        var set = ActiveFileSet<Int>()
        let perDayActive = 3
        var nowValue = fixedNow
        var counts: [Int] = []

        for day in 0..<10 {
            // Today's active files (recent mtime); previous days' files now dormant.
            try makeClaudeCorpus(root: root, active: perDayActive, dormant: 0, tsBase: nowValue, tag: "d\(day)-")
            let active = set.activeFiles(
                roots: [root], window: window, now: nowValue, fileManager: .default,
                matches: { $0.pathExtension == "jsonl" }
            )
            for f in active { set[f.url.path] = .init(offset: 1, state: 0) }
            counts.append(set.entries.count)
            nowValue = nowValue.addingTimeInterval(window + 3_600)   // advance past the window
        }

        // Bounded by the per-day active set, never the 30 cumulative files.
        XCTAssertTrue(counts.allSatisfy { $0 <= perDayActive }, "no upward trend; counts=\(counts)")
        XCTAssertEqual(set.entries.count, perDayActive)
    }

    func testClaudeReaderMemoryPlateausAcrossMultiDayProgression() throws {
        var nowValue = fixedNow
        let reader = ClaudeCodeLogReader(rootURL: root, now: { nowValue })
        let perDayActive = 3
        var counts: [Int] = []

        for day in 0..<10 {
            try makeClaudeCorpus(root: root, active: perDayActive, dormant: 0, tsBase: nowValue, tag: "d\(day)-")
            _ = reader.readNewEvents()
            counts.append(reader.activeFileCount)
            nowValue = nowValue.addingTimeInterval(window + 3_600)
        }

        XCTAssertTrue(counts.allSatisfy { $0 <= perDayActive }, "no upward trend; counts=\(counts)")
        XCTAssertEqual(reader.activeFileCount, perDayActive)
    }

    func testCodexReaderMemoryPlateausAcrossMultiDayProgression() throws {
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        var nowValue = fixedNow
        let reader = CodexLogReader(rootURL: sessions, timeZone: Self.utc, now: { nowValue })
        let perDayActive = 3
        var counts: [Int] = []

        for day in 0..<10 {
            try makeCodexCorpus(root: sessions, active: perDayActive, dormant: 0, tsBase: nowValue, tag: "d\(day)-")
            _ = reader.readNewEvents()
            counts.append(reader.activeFileCount)
            nowValue = nowValue.addingTimeInterval(window + 3_600)
        }

        XCTAssertTrue(counts.allSatisfy { $0 <= perDayActive }, "no upward trend; counts=\(counts)")
        XCTAssertEqual(reader.activeFileCount, perDayActive)
    }
}
