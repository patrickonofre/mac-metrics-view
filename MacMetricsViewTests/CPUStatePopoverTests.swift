import XCTest
@testable import MacMetricsView

@MainActor
final class CPUStatePopoverTests: XCTestCase {

    private func makeState() -> CPUState {
        let suiteName = "MacMetricsViewTests.CPUStatePopover.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        ud.removePersistentDomain(forName: suiteName)
        return CPUState(
            userDefaults: ud,
            accessibilityAuthorization: FakeAccessibilityAuthorization(isTrusted: false)
        )
    }

    func testIsPopoverOpenDefaultsToFalse() {
        XCTAssertFalse(makeState().isPopoverOpen)
    }

    func testSetIsPopoverOpenPublishesValue() {
        let state = makeState()
        
        state.isPopoverOpen = true
        XCTAssertTrue(state.isPopoverOpen)
        
        state.isPopoverOpen = false
        XCTAssertFalse(state.isPopoverOpen)
    }
}
