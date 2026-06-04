import XCTest
@testable import MacMetricsView

/// Covers `ActiveFileSet<State>` (task_01, ADR-002/ADR-003): active-window filtering,
/// single-pass eviction of dormant and deleted paths, prefetch-unavailable fallback to
/// active, multi-root scoping, and the `entries`-count ceiling.
final class ActiveFileSetTests: XCTestCase {

    private var root: URL!
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let window: TimeInterval = 24 * 60 * 60

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("afs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Fixture helpers

    @discardableResult
    private func makeFile(_ name: String, mtimeOffset: TimeInterval, bytes: Int = 16, in dir: URL? = nil) throws -> URL {
        let directory = dir ?? root!
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data(repeating: 0x41, count: bytes).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(mtimeOffset)],
            ofItemAtPath: url.path
        )
        return url
    }

    private func isJSONL(_ url: URL) -> Bool { url.pathExtension == "jsonl" }

    private func scan(_ set: inout ActiveFileSet<Int>, roots: [URL]) -> [(url: URL, size: UInt64)] {
        set.activeFiles(roots: roots, window: window, now: now, fileManager: .default, matches: isJSONL)
    }

    /// macOS canonicalizes the temp dir (`/var` → `/private/var`); the enumerator returns the
    /// canonical form while self-built URLs do not, so compare resolved paths.
    private func norm(_ url: URL) -> String { url.resolvingSymlinksInPath().path }
    private func norm(_ path: String) -> String { URL(fileURLWithPath: path).resolvingSymlinksInPath().path }

    // MARK: - Active-window filtering

    func testFileWithinWindowIsReturnedWithPrefetchedSize() throws {
        try makeFile("a.jsonl", mtimeOffset: -60, bytes: 16)
        var set = ActiveFileSet<Int>()

        let active = scan(&set, roots: [root])

        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.size, 16)
    }

    func testFileOlderThanWindowIsExcluded() throws {
        try makeFile("old.jsonl", mtimeOffset: -window - 60)   // dormant
        try makeFile("new.jsonl", mtimeOffset: -60)            // active
        var set = ActiveFileSet<Int>()

        let active = scan(&set, roots: [root])

        XCTAssertEqual(active.map { $0.url.lastPathComponent }, ["new.jsonl"])
    }

    func testFileExactlyAtWindowEdgeIsActive() throws {
        // mtime == now - window → mtime >= cutoff holds, so it is still active.
        try makeFile("edge.jsonl", mtimeOffset: -window)
        var set = ActiveFileSet<Int>()

        XCTAssertEqual(scan(&set, roots: [root]).count, 1)
    }

    func testNonMatchingNamesAreExcluded() throws {
        try makeFile("keep.jsonl", mtimeOffset: -60)
        try makeFile("skip.txt", mtimeOffset: -60)
        try makeFile("skip.log", mtimeOffset: -60)
        var set = ActiveFileSet<Int>()

        let active = scan(&set, roots: [root])

        XCTAssertEqual(active.map { $0.url.lastPathComponent }, ["keep.jsonl"])
    }

    // MARK: - Eviction

    func testDormantFileEntryIsEvictedInSamePass() throws {
        let file = try makeFile("s.jsonl", mtimeOffset: -60)
        var set = ActiveFileSet<Int>()

        // First pass: active, seed an entry.
        _ = scan(&set, roots: [root])
        set[file.path] = .init(offset: 99, state: 7)
        XCTAssertNotNil(set.entries[file.path])

        // Age the file past the window; next pass must evict it.
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-window - 60)],
            ofItemAtPath: file.path
        )
        let active = scan(&set, roots: [root])

        XCTAssertTrue(active.isEmpty)
        XCTAssertNil(set.entries[file.path])
        XCTAssertEqual(set.entries.count, 0)
    }

    func testDeletedFileEntryIsEvictedInSamePass() throws {
        let file = try makeFile("s.jsonl", mtimeOffset: -60)
        var set = ActiveFileSet<Int>()
        _ = scan(&set, roots: [root])
        set[file.path] = .init(offset: 5, state: 1)

        try FileManager.default.removeItem(at: file)
        _ = scan(&set, roots: [root])

        XCTAssertNil(set.entries[file.path])
        XCTAssertEqual(set.entries.count, 0)
    }

    func testActiveFileEntryIsRetained() throws {
        try makeFile("s.jsonl", mtimeOffset: -60)
        var set = ActiveFileSet<Int>()
        // Key off the enumerator-returned path, exactly as the readers do.
        let key = try XCTUnwrap(scan(&set, roots: [root]).first?.url.path)
        set[key] = .init(offset: 42, state: 3)

        _ = scan(&set, roots: [root])   // still active

        XCTAssertEqual(set.entries[key]?.offset, 42)
        XCTAssertEqual(set.entries[key]?.state, 3)
    }

    // MARK: - Correctness independent of the optimization

    func testFutureMtimeFileTreatedAsActive() throws {
        // Clock skew / non-monotonic mtime: a file dated after `now` satisfies `mtime >=
        // cutoff`, so it is read rather than skipped (ADR-003: future mtime → active).
        try makeFile("future.jsonl", mtimeOffset: +3_600)
        var set = ActiveFileSet<Int>()

        XCTAssertEqual(scan(&set, roots: [root]).map { $0.url.lastPathComponent }, ["future.jsonl"])
    }

    func testNonRegularEntryIsExcluded() throws {
        // A symlink (even matching `*.jsonl`) is not a regular file; the scan must not return
        // it for reading. The `else` branch (unreadable resource values → treated active) is
        // a defensive fallback that no real regular file deterministically triggers.
        let target = try makeFile("real-target.jsonl", mtimeOffset: -60)
        let link = root.appendingPathComponent("link.jsonl")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        var set = ActiveFileSet<Int>()

        let active = scan(&set, roots: [root])

        XCTAssertEqual(active.map { $0.url.lastPathComponent }, ["real-target.jsonl"])
    }

    // MARK: - Multi-root scoping (Codex date dirs)

    func testMultiRootScanReturnsUnionAndEvictsOutsideAllRoots() throws {
        let dayA = root.appendingPathComponent("2026/02/23", isDirectory: true)
        let dayB = root.appendingPathComponent("2026/02/22", isDirectory: true)
        let dayOld = root.appendingPathComponent("2025/01/01", isDirectory: true)
        let fileA = try makeFile("rollout-a.jsonl", mtimeOffset: -60, in: dayA)
        let fileB = try makeFile("rollout-b.jsonl", mtimeOffset: -120, in: dayB)
        let fileOld = try makeFile("rollout-old.jsonl", mtimeOffset: -60, in: dayOld)
        var set = ActiveFileSet<Int>()

        // Seed an entry for the out-of-scope file as if a previous run had tracked it.
        set[fileOld.path] = .init(offset: 1, state: 1)

        let active = set.activeFiles(
            roots: [dayA, dayB],   // dayOld intentionally not a root
            window: window, now: now, fileManager: .default, matches: isJSONL
        )

        XCTAssertEqual(Set(active.map { norm($0.url) }), [norm(fileA), norm(fileB)])
        XCTAssertNil(set.entries[fileOld.path])          // evicted: outside all roots
        XCTAssertEqual(set.entries.count, 0)
    }

    func testNonExistentRootIsSkipped() throws {
        try makeFile("present.jsonl", mtimeOffset: -60)
        let missing = root.appendingPathComponent("does-not-exist", isDirectory: true)
        var set = ActiveFileSet<Int>()

        let active = set.activeFiles(
            roots: [missing, root], window: window, now: now, fileManager: .default, matches: isJSONL
        )

        XCTAssertEqual(active.count, 1)
    }

    // MARK: - Ceiling invariant

    func testEntriesCountEqualsActiveSetNotHistoricalCount() throws {
        // Many dormant files + a few active ones; after a pass, entries track only the active.
        for i in 0..<50 { try makeFile("dormant-\(i).jsonl", mtimeOffset: -window - 60) }
        var activeFiles: [URL] = []
        for i in 0..<3 { activeFiles.append(try makeFile("active-\(i).jsonl", mtimeOffset: -60)) }

        var set = ActiveFileSet<Int>()
        let active = scan(&set, roots: [root])
        // Simulate readers seeding entries for the files they actually read.
        for f in active { set[f.url.path] = .init(offset: 1, state: 0) }

        XCTAssertEqual(active.count, 3)
        // Re-scan: entries stay bounded to the active set, never the 53 total files.
        _ = scan(&set, roots: [root])
        XCTAssertEqual(set.entries.count, 3)
        XCTAssertEqual(Set(set.entries.keys.map { norm($0) }), Set(activeFiles.map { norm($0) }))
    }
}
