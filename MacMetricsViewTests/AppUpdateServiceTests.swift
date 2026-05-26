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
        service.setAutomaticChecks(true)
        service.setAutomaticChecks(false)

        XCTAssertFalse(service.canCheckForUpdates)
    }
}
