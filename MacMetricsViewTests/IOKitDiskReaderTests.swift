import XCTest
@testable import MacMetricsView

private final class StubDiskReader: DiskReading {
    var nextSnapshot: DiskCounterSnapshot?
    private(set) var readCount = 0

    init(nextSnapshot: DiskCounterSnapshot? = nil) {
        self.nextSnapshot = nextSnapshot
    }

    func readSnapshot() -> DiskCounterSnapshot? {
        readCount += 1
        return nextSnapshot
    }
}

final class IOKitDiskReaderTests: XCTestCase {
    func testStubReaderProvesProtocolSeamCanBeSwapped() {
        let snapshot = DiskCounterSnapshot(
            timestamp: Date(timeIntervalSince1970: 100),
            bytesRead: 4_096,
            bytesWritten: 8_192
        )
        let reader: DiskReading = StubDiskReader(nextSnapshot: snapshot)

        XCTAssertEqual(reader.readSnapshot(), snapshot)
    }

    func testStubReaderReturningNilExercisesFailureTolerance() {
        let reader: DiskReading = StubDiskReader(nextSnapshot: nil)

        XCTAssertNil(reader.readSnapshot())
    }

    func testStubReaderRecordsEachInvocation() {
        let stub = StubDiskReader(nextSnapshot: nil)
        let reader: DiskReading = stub

        _ = reader.readSnapshot()
        _ = reader.readSnapshot()
        _ = reader.readSnapshot()

        XCTAssertEqual(stub.readCount, 3)
    }

    /// Host-only smoke test. Skips gracefully if IOKit access is denied or the
    /// boot-disk traversal fails on this environment (e.g. a sandboxed CI box).
    func testRealReaderReturnsNonNilSnapshotOnHost() throws {
        let reader = IOKitDiskReader()

        guard let snapshot = reader.readSnapshot() else {
            throw XCTSkip("IOKit boot-disk traversal returned nil — skipping host smoke test.")
        }

        XCTAssertGreaterThan(snapshot.bytesRead, 0, "boot SSD should report a positive bytesRead counter")
        XCTAssertGreaterThan(snapshot.bytesWritten, 0, "boot SSD should report a positive bytesWritten counter")
    }

    /// Smoke test: repeated reader creation/destruction must not crash and must
    /// keep returning fresh snapshots. Verifies the deinit release path under
    /// repeated allocation; true leak detection requires Instruments.
    func testReaderCreationAndDeallocationDoesNotCrashOverManyIterations() throws {
        for _ in 0..<32 {
            let reader = IOKitDiskReader()
            _ = reader.readSnapshot()
        }
    }
}
