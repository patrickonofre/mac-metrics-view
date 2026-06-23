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
    
    func testPopoverLifecycleWiringStartStopSampling() {
        let suiteName = "MacMetricsViewTests.CPUStatePopoverLifecycle.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        ud.removePersistentDomain(forName: suiteName)
        let processReader = FakeProcessReader()
        let state = CPUState(
            userDefaults: ud,
            accessibilityAuthorization: FakeAccessibilityAuthorization(isTrusted: false),
            processReader: processReader,
            samplingExecutor: InlineSamplingExecutor()
        )
        
        // Simulating PopoverView.onAppear
        state.beginProcessSampling()
        XCTAssertEqual(processReader.readCount, 1, "onAppear should start process sampling and read baseline")
        
        // Simulating PopoverView.onDisappear
        state.endProcessSampling()
        // Advancing time or calling tick after end should not perform further reads
        state.processSamplingTick()
        XCTAssertEqual(processReader.readCount, 1, "onDisappear should stop sampling and prevent further ticks")
    }

    func testSetUpdateRateClampsAndPersists() {
        let state = makeState()
        
        var displayChangeCalled = false
        state.onDisplayChange = {
            displayChangeCalled = true
        }
        
        state.setUpdateRate(3)
        XCTAssertEqual(state.updateRate, 3)
        XCTAssertTrue(displayChangeCalled)
        
        displayChangeCalled = false
        state.setUpdateRate(5) // invalid, should clamp to 1
        XCTAssertEqual(state.updateRate, 1)
        XCTAssertTrue(displayChangeCalled)
        
        displayChangeCalled = false
        state.setUpdateRate(0) // invalid, should clamp to 1
        XCTAssertEqual(state.updateRate, 1)
        XCTAssertTrue(displayChangeCalled)
    }
    
    func testIsPopoverOpenTriggersOnPopoverOpenChange() {
        let state = makeState()
        
        var callbackValue: Bool?
        state.onPopoverOpenChange = { open in
            callbackValue = open
        }
        
        state.isPopoverOpen = true
        XCTAssertEqual(callbackValue, true)
        
        state.isPopoverOpen = false
        XCTAssertEqual(callbackValue, false)
    }
}
