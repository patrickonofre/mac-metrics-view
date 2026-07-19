import XCTest
import AppKit
@testable import MacMetricsView

/// Wiring tests for the lid-close quit failsafe (feature `lid-close-keep-awake`,
/// LIDC-11): `applicationWillTerminate` must clear the system sleep-disabled flag
/// before the process exits. Same pattern as `AppDelegateBatteryWiringTests` — the
/// real AppDelegate/CPUState wiring with fakes injected at the service seams.
@MainActor
final class AppDelegateLidCloseWiringTests: XCTestCase {

    // MARK: - Fakes

    private final class FakeSleepAssertionService: SleepAssertionControlling {
        func activate() -> Bool { true }
        func deactivate() {}
    }

    private final class FakeLidCloseService: LidCloseSleepControlling {
        private(set) var activateCalls = 0
        private(set) var deactivateCalls = 0

        func activate() async -> LidCloseActivationOutcome {
            activateCalls += 1
            return .active
        }

        func deactivate() async {
            deactivateCalls += 1
        }
    }

    private final class FakePowerSourceMonitor: PowerSourceMonitoring {
        var onChange: ((PowerSourceSnapshot) -> Void)?
        func start() {}
        func stop() {}
    }

    // MARK: - Helpers

    /// Builds an AppDelegate whose CPUState carries the injected lid-close fakes.
    /// A fresh defaults suite keeps keep-awake persistence out of the user's real
    /// preferences; the fake assertion service keeps IOPM untouched.
    private func makeAppDelegate(helper: FakeLidCloseService) -> AppDelegate {
        let appDelegate = AppDelegate()
        // The bounded run-loop pump cannot drain the main actor under XCTest (the
        // test's own main-actor frame holds it), so it is zeroed and the tests await
        // `lidCloseTerminationTask` + `settleLidCloseTransitions()` instead.
        appDelegate.lidCloseTerminationPumpTimeout = 0
        appDelegate.state = CPUState(
            userDefaults: UserDefaults(suiteName: "AppDelegateLidCloseWiringTests.\(UUID().uuidString)")!,
            sleepAssertionService: FakeSleepAssertionService(),
            lidCloseService: helper,
            powerSourceMonitor: FakePowerSourceMonitor()
        )
        return appDelegate
    }

    private func terminate(_ appDelegate: AppDelegate) async {
        appDelegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        await appDelegate.lidCloseTerminationTask?.value
        await appDelegate.state.keepAwake.settleLidCloseTransitions()
    }

    // MARK: - LIDC-11

    // LIDC-11: quitting while the sub-mode is active must set the sleep-disabled flag
    // to false (helper deactivate, exactly once) and leave the sub-mode off.
    func testTerminateDeactivatesActiveLidCloseSubMode() async {
        let helper = FakeLidCloseService()
        let appDelegate = makeAppDelegate(helper: helper)
        appDelegate.state.keepAwake.setActive(true)
        await appDelegate.state.keepAwake.setLidCloseActive(true)
        XCTAssertEqual(appDelegate.state.keepAwake.lidClose, .active, "precondition: sub-mode active")

        await terminate(appDelegate)

        XCTAssertEqual(appDelegate.state.keepAwake.lidClose, .off, "terminate must leave the sub-mode off (LIDC-11)")
        XCTAssertEqual(helper.deactivateCalls, 1, "terminate must clear the flag exactly once (LIDC-11)")
    }

    // Guard: quitting with the sub-mode off must not contact the helper at all —
    // no spurious daemon launch on every app quit.
    func testTerminateWithSubModeOffMakesNoHelperCall() async {
        let helper = FakeLidCloseService()
        let appDelegate = makeAppDelegate(helper: helper)
        appDelegate.state.keepAwake.setActive(true)

        await terminate(appDelegate)

        XCTAssertEqual(helper.activateCalls, 0)
        XCTAssertEqual(helper.deactivateCalls, 0, "no helper call when the sub-mode was never active")
    }

    // The failsafe only touches the sub-mode: base keep-awake's persisted preference
    // survives quit untouched (KAWK-05 unaffected by the lid-close failsafe).
    func testTerminateLeavesBaseKeepAwakePreferenceUntouched() async {
        let helper = FakeLidCloseService()
        let defaults = UserDefaults(suiteName: "AppDelegateLidCloseWiringTests.\(UUID().uuidString)")!
        let appDelegate = AppDelegate()
        appDelegate.lidCloseTerminationPumpTimeout = 0
        appDelegate.state = CPUState(
            userDefaults: defaults,
            sleepAssertionService: FakeSleepAssertionService(),
            lidCloseService: helper,
            powerSourceMonitor: FakePowerSourceMonitor()
        )
        appDelegate.state.keepAwake.setActive(true)
        await appDelegate.state.keepAwake.setLidCloseActive(true)

        await terminate(appDelegate)

        XCTAssertTrue(KeepAwakeSettings.load(from: defaults).isActive, "stored base preference must survive quit")
        XCTAssertTrue(appDelegate.state.keepAwake.isActive, "base keep-awake state untouched by the lid-close failsafe")
    }
}
