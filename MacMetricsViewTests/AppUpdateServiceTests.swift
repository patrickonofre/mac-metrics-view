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
}
