import XCTest
@testable import MacMetricsView

final class AccessibilityNudgeTrackerTests: XCTestCase {

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "MacMetricsViewTests.NudgeTracker.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        ud.removePersistentDomain(forName: suiteName)
        return ud
    }

    // MARK: - shouldNudge

    func testFreshTrackerShouldNudgeForAnyVersion() {
        let tracker = AccessibilityNudgeTracker()
        XCTAssertTrue(tracker.shouldNudge(forVersion: "1.4.0"))
        XCTAssertTrue(tracker.shouldNudge(forVersion: "2.0.0"))
    }

    func testRecordedVersionShouldNotNudgeAgain() {
        let tracker = AccessibilityNudgeTracker().recordingNudge(version: "1.4.0")
        XCTAssertFalse(tracker.shouldNudge(forVersion: "1.4.0"))
    }

    func testRecordedVersionStillNudgesForNewerVersion() {
        let tracker = AccessibilityNudgeTracker().recordingNudge(version: "1.4.0")
        XCTAssertTrue(tracker.shouldNudge(forVersion: "1.5.0"))
    }

    func testRecordingNudgeStoresVersion() {
        XCTAssertEqual(AccessibilityNudgeTracker().recordingNudge(version: "1.4.0").lastNudgedVersion, "1.4.0")
    }

    // MARK: - Persistence

    func testLoadDefaultsToNilWhenAbsent() {
        XCTAssertNil(AccessibilityNudgeTracker.load(from: makeUserDefaults()).lastNudgedVersion)
    }

    func testSaveThenLoadRoundTrips() {
        let ud = makeUserDefaults()
        AccessibilityNudgeTracker(lastNudgedVersion: "1.4.0").save(to: ud)
        XCTAssertEqual(AccessibilityNudgeTracker.load(from: ud).lastNudgedVersion, "1.4.0")
    }

    func testSaveNilClearsStoredValue() {
        let ud = makeUserDefaults()
        AccessibilityNudgeTracker(lastNudgedVersion: "1.4.0").save(to: ud)
        AccessibilityNudgeTracker(lastNudgedVersion: nil).save(to: ud)
        XCTAssertNil(AccessibilityNudgeTracker.load(from: ud).lastNudgedVersion)
    }

    // MARK: - Integration: round-trip across instances

    func testRecordedNudgeObservedByASecondInstanceFromSameSuite() {
        let ud = makeUserDefaults()

        // First instance records the nudge for the current version.
        let first = AccessibilityNudgeTracker.load(from: ud)
        XCTAssertTrue(first.shouldNudge(forVersion: "1.4.0"))
        first.recordingNudge(version: "1.4.0").save(to: ud)

        // A second instance loaded from the same suite sees it as already fired.
        let second = AccessibilityNudgeTracker.load(from: ud)
        XCTAssertFalse(second.shouldNudge(forVersion: "1.4.0"))
        XCTAssertTrue(second.shouldNudge(forVersion: "1.5.0"))
    }
}
