import XCTest
@testable import MacMetricsView

final class LibprocProcessReaderTests: XCTestCase {
    func testReaderConformsToProcessReading() {
        let reader: Any = LibprocProcessReader()
        XCTAssertTrue(reader is ProcessReading)
    }
    
    func testProcessNameParserNullTermination() {
        // Normal C-string with null terminator
        let normalBytes: [CChar] = [65, 66, 67, 0, 68, 69] // "ABC" followed by null and extra chars
        XCTAssertEqual(ProcessNameParser.parseName(from: normalBytes), "ABC")
    }
    
    func testProcessNameParserNoNullTermination() {
        // C-string without null terminator
        let noNullBytes: [CChar] = [72, 69, 76, 76, 79] // "HELLO"
        XCTAssertEqual(ProcessNameParser.parseName(from: noNullBytes), "HELLO")
    }
    
    func testProcessNameParserEmptyInput() {
        // Empty array
        let emptyBytes: [CChar] = []
        XCTAssertEqual(ProcessNameParser.parseName(from: emptyBytes), "")
    }
    
    func testProcessNameParserLeadingNull() {
        // String starting with a null byte
        let leadingNull: [CChar] = [0, 65, 66]
        XCTAssertEqual(ProcessNameParser.parseName(from: leadingNull), "")
    }
    
    func testLiveSystemSmokeManual() {
        // Documented manual integration/smoke check. Since this runs on the live machine
        // during testing, we can assert some basic invariants that should always hold.
        let reader = LibprocProcessReader()
        guard let snapshot = reader.readSnapshot() else {
            XCTFail("Failed to read snapshot from live system")
            return
        }
        
        // Assert invariants
        XCTAssertGreaterThan(snapshot.entries.count, 0, "Live system should have at least one process")
        
        // Find our own process
        let currentPid = getpid()
        guard let currentEntry = snapshot.entries[currentPid] else {
            XCTFail("Live snapshot should contain the test runner's own PID (\(currentPid))")
            return
        }
        
        XCTAssertFalse(currentEntry.name.isEmpty, "Test runner process name should not be empty")
        XCTAssertGreaterThan(currentEntry.cpuNanos, 0, "Test runner process should have consumed CPU time")
        
        // Verify names are resolved reasonably
        for (pid, entry) in snapshot.entries {
            XCTAssertGreaterThan(pid, 0, "PIDs must be positive integers")
            XCTAssertFalse(entry.name.isEmpty, "Process name should not be empty")
        }
    }
}
