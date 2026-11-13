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

    func testLegacyAmbientPreferencesRemainInertAndPreserved() {
        let legacyPreferences: [[String: Any]] = [
            [
                "AmbientThemeSettings.isEnabled": true,
                "AmbientThemeSettings.lowLux": 175.0,
                "AmbientThemeSettings.highLux": 240.0,
                "AmbientThemeSettings.dwellSeconds": 20.0
            ],
            [
                "AmbientThemeSettings.isEnabled": true,
                "AmbientThemeSettings.lowLux": "invalid",
                "AmbientThemeSettings.highLux": -1.0,
                "AmbientThemeSettings.dwellSeconds": ["invalid"]
            ]
        ]

        for legacy in legacyPreferences {
            let suiteName = "MacMetricsViewTests.LegacyAmbient.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            defer { defaults.removePersistentDomain(forName: suiteName) }
            legacy.forEach { defaults.set($0.value, forKey: $0.key) }
            let display = MetricDisplaySettings(identifierStyle: .labels, diskMenuBarMetric: .split, updateRate: 3)
            display.save(to: defaults)
            let visibility = MetricVisibilitySettings.firstRunPreset
            visibility.save(to: defaults)

            let state = CPUState(
                userDefaults: defaults,
                accessibilityAuthorization: FakeAccessibilityAuthorization(isTrusted: false)
            )

            XCTAssertFalse(state.isPopoverOpen)
            XCTAssertEqual(state.metrics.visibility, visibility)
            XCTAssertEqual(state.metrics.display, display)
            state.metrics.setUpdateRate(2)
            XCTAssertEqual(MetricDisplaySettings.load(from: defaults).updateRate, 2)
            let preserved = defaults.dictionaryRepresentation().filter { legacy[$0.key] != nil }
            XCTAssertEqual(preserved as NSDictionary, legacy as NSDictionary)
        }
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
        state.metrics.beginProcessSampling()
        XCTAssertEqual(processReader.readCount, 1, "onAppear should start process sampling and read baseline")
        
        // Simulating PopoverView.onDisappear
        state.metrics.endProcessSampling()
        // Advancing time or calling tick after end should not perform further reads
        state.metrics.processSamplingTick()
        XCTAssertEqual(processReader.readCount, 1, "onDisappear should stop sampling and prevent further ticks")
    }

    func testSetUpdateRateClampsAndPersists() {
        let state = makeState()
        
        var displayChangeCalled = false
        state.onDisplayChange = {
            displayChangeCalled = true
        }
        
        state.metrics.setUpdateRate(3)
        XCTAssertEqual(state.metrics.updateRate, 3)
        XCTAssertTrue(displayChangeCalled)
        
        displayChangeCalled = false
        state.metrics.setUpdateRate(5) // invalid, should clamp to 1
        XCTAssertEqual(state.metrics.updateRate, 1)
        XCTAssertTrue(displayChangeCalled)
        
        displayChangeCalled = false
        state.metrics.setUpdateRate(0) // invalid, should clamp to 1
        XCTAssertEqual(state.metrics.updateRate, 1)
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
