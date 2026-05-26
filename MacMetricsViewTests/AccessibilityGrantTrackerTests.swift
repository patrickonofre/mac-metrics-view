import XCTest
@testable import MacMetricsView

final class AccessibilityGrantTrackerTests: XCTestCase {

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "MacMetricsViewTests.GrantTracker.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        ud.removePersistentDomain(forName: suiteName)
        return ud
    }

    // MARK: - wasResetByUpdate

    func testNeverGrantedIsNotAReset() {
        let tracker = AccessibilityGrantTracker(lastGrantedVersion: nil)
        XCTAssertFalse(tracker.wasResetByUpdate(isTrusted: false, currentVersion: "1.1.0"))
    }

    func testTrustedIsNeverAReset() {
        let tracker = AccessibilityGrantTracker(lastGrantedVersion: "1.0.0")
        XCTAssertFalse(tracker.wasResetByUpdate(isTrusted: true, currentVersion: "1.1.0"))
    }

    func testRevokeOnSameVersionIsNotAReset() {
        // Granted then revoked on the same build → ordinary first-grant prompt,
        // not the update-reset guidance.
        let tracker = AccessibilityGrantTracker(lastGrantedVersion: "1.1.0")
        XCTAssertFalse(tracker.wasResetByUpdate(isTrusted: false, currentVersion: "1.1.0"))
    }

    func testGrantOnEarlierVersionLostAfterUpdateIsAReset() {
        let tracker = AccessibilityGrantTracker(lastGrantedVersion: "1.0.0")
        XCTAssertTrue(tracker.wasResetByUpdate(isTrusted: false, currentVersion: "1.1.0"))
    }

    // MARK: - recordingGrant

    func testRecordingGrantUpdatesVersion() {
        let tracker = AccessibilityGrantTracker(lastGrantedVersion: "1.0.0")
        XCTAssertEqual(tracker.recordingGrant(version: "1.1.0").lastGrantedVersion, "1.1.0")
    }

    // MARK: - Persistence

    func testLoadDefaultsToNilWhenAbsent() {
        XCTAssertNil(AccessibilityGrantTracker.load(from: makeUserDefaults()).lastGrantedVersion)
    }

    func testSaveThenLoadRoundTrips() {
        let ud = makeUserDefaults()
        AccessibilityGrantTracker(lastGrantedVersion: "1.2.3").save(to: ud)
        XCTAssertEqual(AccessibilityGrantTracker.load(from: ud).lastGrantedVersion, "1.2.3")
    }

    func testSaveNilClearsStoredValue() {
        let ud = makeUserDefaults()
        AccessibilityGrantTracker(lastGrantedVersion: "1.2.3").save(to: ud)
        AccessibilityGrantTracker(lastGrantedVersion: nil).save(to: ud)
        XCTAssertNil(AccessibilityGrantTracker.load(from: ud).lastGrantedVersion)
    }
}
