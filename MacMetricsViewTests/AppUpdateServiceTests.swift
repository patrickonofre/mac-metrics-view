import XCTest
@testable import MacMetricsView

@MainActor
final class AppUpdateServiceTests: XCTestCase {
    func testFactoryResolvesToNoOpUnderSPM() {
        let service = makeAppUpdateService()

        // Under `swift test` Sparkle is not linked, so the factory must fall back
        // to the inert implementation.
        XCTAssertTrue(service is NoOpUpdateService)
    }

    func testNoOpCannotCheckAndDoesNothing() {
        let service = NoOpUpdateService()

        XCTAssertFalse(service.canCheckForUpdates)

        // No crash, no observable effect.
        service.checkForUpdates()
        service.probeForUpdateInformation()

        XCTAssertFalse(service.canCheckForUpdates)
    }

    func testNoOpNeverFiresAvailableVersionChange() {
        let service = NoOpUpdateService()
        var fired = false
        service.onAvailableVersionChange = { _ in fired = true }

        service.probeForUpdateInformation()

        XCTAssertFalse(fired)
    }

    func testStateUpdateOnAvailableVersionChangeCallback() {
        let suiteName = "MacMetricsViewTests.UpdateService.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        ud.removePersistentDomain(forName: suiteName)
        let state = CPUState(
            userDefaults: ud,
            accessibilityAuthorization: FakeAccessibilityAuthorization(isTrusted: false)
        )
        
        let service = NoOpUpdateService()
        
        // Wire up like AppDelegate does
        service.onAvailableVersionChange = { version in
            state.setAvailableUpdateVersion(version)
        }
        
        // Trigger manually
        service.onAvailableVersionChange?("1.9.1")
        XCTAssertEqual(state.availableUpdateVersion, "1.9.1")
        
        service.onAvailableVersionChange?(nil)
        XCTAssertNil(state.availableUpdateVersion)
    }
}
