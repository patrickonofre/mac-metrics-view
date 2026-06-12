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

    // MARK: - Cost computation at max-retention volume (Phase 1 gate)

    /// Cost math is O(events) per UI refresh, bounded by the 25h retention horizon
    /// (ADR-003). This gate feeds a max-retention-scale synthetic event set through
    /// `TokenCostCalculator` and asserts the exact expected total — proving the
    /// computation stays correct and tractable at the volume ceiling.
    func testCostComputationAtMaxRetentionEventVolume() {
        let count = 100_000   // well above a realistic 25h event volume
        var events: [TokenUsageEvent] = []
        events.reserveCapacity(count)
        for index in 0..<count {
            let isClaude = index % 2 == 0
            events.append(TokenUsageEvent(
                timestamp: fixedNow.addingTimeInterval(-Double(index % 86_400)),
                model: isClaude ? "claude-opus-4-8" : "gpt-5-codex",
                inputTokens: 1_000,
                outputTokens: 500,
                cacheReadTokens: 2_000,
                cacheCreationTokens: 100,
                reasoningTokens: isClaude ? 0 : 300,
                sessionID: "s\(index % 8)",
                projectDir: "p\(index % 4)"
            ))
        }

        let breakdown = TokenCostCalculator.cost(of: events)

        // Per-event: opus 0.005 + 0.0125 + 0.001 + 0.000625 = 0.019125 USD;
        // codex (0.00125 + 0.005 + 0.00025 + 0.000125) + reasoning 0.003 = 0.009625 USD.
        let expected = Double(count / 2) * 0.019125 + Double(count / 2) * 0.009625
        XCTAssertEqual(breakdown.totalUSD, expected, accuracy: 1e-6)
        XCTAssertEqual(breakdown.perModelUSD.count, 2)
        XCTAssertEqual(breakdown.unpricedTokens, 0)
    }

    // MARK: - Burn-rate computation at max-retention volume (Phase 2 gate)

    /// Burn-rate math is O(events) per recompute, bounded by the 25h retention horizon
    /// (ADR-004). This gate feeds a max-retention-scale synthetic event set through
    /// `TokenBurnRate.compute` and asserts the exact expected figures — proving the
    /// computation stays correct and tractable at the volume ceiling.
    func testBurnRateComputationAtMaxRetentionEventVolume() throws {
        let count = 100_000   // well above a realistic 25h event volume
        var events: [TokenUsageEvent] = []
        events.reserveCapacity(count)
        for index in 0..<count {
            // First half lands inside the trailing hour (offsets 0–2999s); second half
            // sits outside it (offsets 4000–83999s) but within retention.
            let offset = index < count / 2
                ? Double(index % 3_000)
                : 4_000 + Double(index % 80_000)
            events.append(TokenUsageEvent(
                timestamp: fixedNow.addingTimeInterval(-offset),
                model: "claude-opus-4-8",
                inputTokens: 1_000,
                outputTokens: 500,
                cacheReadTokens: 2_000,
                cacheCreationTokens: 100,
                sessionID: "s\(index % 8)",
                projectDir: "p\(index % 4)"
            ))
        }

        let breakdown = try XCTUnwrap(TokenBurnRate.compute(events: events, now: fixedNow))

        // 50k in-window events × 1500 usage tokens; per-event cost (opus 4.8):
        // 0.005 + 0.0125 + 0.001 + 0.000625 = 0.019125 USD.
        let inWindow = Double(count / 2)
        XCTAssertEqual(breakdown.tokensPerHour, inWindow * 1_500, accuracy: 1e-6)
        XCTAssertEqual(breakdown.costPerHourUSD, inWindow * 0.019125, accuracy: 1e-6)
        XCTAssertEqual(breakdown.costPerDayUSD, inWindow * 0.019125 * 24, accuracy: 1e-5)
    }

    // MARK: - Block computation at max-retention volume (Phase 3 gate)

    /// Block math is O(n log n) per recompute, bounded by the 25h retention
    /// horizon (ADR-006). This gate feeds a max-retention-scale synthetic event
    /// set through `TokenRateLimitWindow.activeBlock` and asserts the exact
    /// expected block — proving the computation stays correct and tractable at
    /// the volume ceiling.
    func testBlockComputationAtMaxRetentionEventVolume() throws {
        let count = 100_000   // well above a realistic 25h event volume
        // Whole-hour anchor so the expected block boundaries are exact dates.
        let hour = Date(timeIntervalSince1970: (1_700_000_000.0 / 3_600).rounded(.down) * 3_600)
        var events: [TokenUsageEvent] = []
        events.reserveCapacity(count)
        for index in 0..<count {
            // First half: offsets 1–3,599s back → all inside the block opened at
            // `hour − 1h` (first event floored to the hour). Second half: 7–24h
            // back, leaving a >5h gap that resyncs the chain at the active block.
            let offset = index < count / 2
                ? 1 + Double(index % 3_599)
                : 25_200 + Double(index % 61_200)
            events.append(TokenUsageEvent(
                timestamp: hour.addingTimeInterval(-offset),
                model: "claude-opus-4-8",
                inputTokens: 1_000,
                outputTokens: 500,
                cacheReadTokens: 2_000,
                cacheCreationTokens: 100,
                sessionID: "s\(index % 8)",
                projectDir: "p\(index % 4)"
            ))
        }

        let block = try XCTUnwrap(TokenRateLimitWindow.activeBlock(events: events, now: hour))

        XCTAssertEqual(block.start, hour.addingTimeInterval(-3_600))
        XCTAssertEqual(block.end, hour.addingTimeInterval(-3_600 + 5 * 3_600))
        XCTAssertEqual(block.usage.input, 50_000 * 1_000)
        XCTAssertEqual(block.usage.output, 50_000 * 500)
        XCTAssertEqual(block.usage.cacheRead, 50_000 * 2_000)
        // Per-event cost (opus 4.8): 0.005 + 0.0125 + 0.001 + 0.000625 = 0.019125.
        XCTAssertEqual(block.costUSD, 50_000 * 0.019125, accuracy: 1e-5)
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
