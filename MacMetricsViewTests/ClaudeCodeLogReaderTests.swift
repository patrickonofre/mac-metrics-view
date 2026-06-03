import XCTest
@testable import MacMetricsView

final class ClaudeCodeLogReaderTests: XCTestCase {

    private var root: URL!
    private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ccreader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Fixture helpers

    private func projectDir(_ name: String) throws -> URL {
        let dir = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func usageLine(
        at offset: TimeInterval,
        model: String = "claude-opus-4-8",
        input: Int = 0,
        output: Int = 0,
        cacheRead: Int = 0,
        cacheCreation: Int = 0
    ) -> String {
        let timestamp = Self.iso.string(from: fixedNow.addingTimeInterval(offset))
        return """
        {"timestamp":"\(timestamp)","message":{"model":"\(model)","usage":{"input_tokens":\(input),"output_tokens":\(output),"cache_read_input_tokens":\(cacheRead),"cache_creation_input_tokens":\(cacheCreation)}}}
        """
    }

    private func write(_ lines: [String], to file: URL) throws {
        let body = lines.joined(separator: "\n") + "\n"
        try body.data(using: .utf8)!.write(to: file)
    }

    private func append(_ lines: [String], to file: URL) throws {
        let body = lines.joined(separator: "\n") + "\n"
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: body.data(using: .utf8)!)
    }

    private func makeReader() -> ClaudeCodeLogReader {
        ClaudeCodeLogReader(rootURL: root, now: { self.fixedNow })
    }

    // MARK: - Tests

    func testValidUsageLineParsesIntoEvent() throws {
        let file = try projectDir("p1").appendingPathComponent("s1.jsonl")
        try write([usageLine(at: -60, input: 11, output: 22, cacheRead: 33, cacheCreation: 44)], to: file)

        let events = makeReader().readNewEvents()

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.inputTokens, 11)
        XCTAssertEqual(events.first?.outputTokens, 22)
        XCTAssertEqual(events.first?.cacheReadTokens, 33)
        XCTAssertEqual(events.first?.cacheCreationTokens, 44)
        XCTAssertEqual(events.first?.model, "claude-opus-4-8")
        XCTAssertEqual(events.first?.timestamp, fixedNow.addingTimeInterval(-60))
    }

    func testInvalidJSONLineIsSkippedWithoutAbortingFile() throws {
        let file = try projectDir("p1").appendingPathComponent("s1.jsonl")
        try write(["{ this is not json", usageLine(at: -30, input: 5)], to: file)

        let events = makeReader().readNewEvents()

        XCTAssertEqual(events.map(\.inputTokens), [5])
    }

    func testLineWithoutUsageIsSkipped() throws {
        let file = try projectDir("p1").appendingPathComponent("s1.jsonl")
        let userLine = #"{"timestamp":"2026-06-03T00:00:00.000Z","message":{"role":"user","content":"hi"}}"#
        try write([userLine, usageLine(at: -10, input: 9)], to: file)

        let events = makeReader().readNewEvents()

        XCTAssertEqual(events.map(\.inputTokens), [9])
    }

    func testSecondReadReturnsOnlyNewlyAppendedEvents() throws {
        let file = try projectDir("p1").appendingPathComponent("s1.jsonl")
        try write([usageLine(at: -60, input: 1)], to: file)
        let reader = makeReader()

        XCTAssertEqual(reader.readNewEvents().map(\.inputTokens), [1])

        try append([usageLine(at: -30, input: 2), usageLine(at: -10, input: 3)], to: file)

        XCTAssertEqual(reader.readNewEvents().map(\.inputTokens), [2, 3])
        XCTAssertEqual(reader.readNewEvents(), [])   // nothing new
    }

    func testFileTruncatedBelowOffsetIsReReadFromZero() throws {
        let file = try projectDir("p1").appendingPathComponent("s1.jsonl")
        try write([usageLine(at: -60, input: 1), usageLine(at: -50, input: 2)], to: file)
        let reader = makeReader()
        _ = reader.readNewEvents()

        // Rotation: replace with a shorter file.
        try write([usageLine(at: -5, input: 7)], to: file)

        XCTAssertEqual(reader.readNewEvents().map(\.inputTokens), [7])
    }

    func testFirstCallBackfillsOnlyRetentionTail() throws {
        let file = try projectDir("p1").appendingPathComponent("s1.jsonl")
        try write([
            usageLine(at: -48 * 3_600, input: 999),   // 48h ago — outside 24h tail
            usageLine(at: -1 * 3_600, input: 42)       // 1h ago — inside tail
        ], to: file)

        let events = makeReader().readNewEvents()

        XCTAssertEqual(events.map(\.inputTokens), [42])
    }

    func testSessionAndProjectAreDerivedFromPath() throws {
        let file = try projectDir("proj-encoded").appendingPathComponent("abc-123.jsonl")
        try write([usageLine(at: -60, input: 1)], to: file)

        let event = makeReader().readNewEvents().first

        XCTAssertEqual(event?.sessionID, "abc-123")
        XCTAssertEqual(event?.projectDir, "proj-encoded")
    }

    func testMissingRootReturnsEmpty() {
        let reader = ClaudeCodeLogReader(
            rootURL: root.appendingPathComponent("does-not-exist", isDirectory: true),
            now: { self.fixedNow }
        )

        XCTAssertEqual(reader.readNewEvents(), [])
    }

    // MARK: - Integration

    func testTwoProjectCorpusAcrossMultiplePolls() throws {
        let fileA = try projectDir("pA").appendingPathComponent("sA.jsonl")
        let fileB = try projectDir("pB").appendingPathComponent("sB.jsonl")
        try write([usageLine(at: -120, input: 10)], to: fileA)
        try write([usageLine(at: -110, input: 20)], to: fileB)
        let reader = makeReader()

        let first = reader.readNewEvents()
        XCTAssertEqual(first.count, 2)
        XCTAssertEqual(Set(first.map(\.projectDir)), ["pA", "pB"])
        XCTAssertEqual(first.reduce(0) { $0 + $1.inputTokens }, 30)

        try append([usageLine(at: -10, input: 5)], to: fileA)
        let second = reader.readNewEvents()
        XCTAssertEqual(second.map(\.inputTokens), [5])
        XCTAssertEqual(second.first?.projectDir, "pA")
    }
}
