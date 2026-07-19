import XCTest
@testable import MacMetricsView

/// Tests for `KeepAwakeModel`'s lid-close sub-mode (feature `lid-close-keep-awake`,
/// LIDC-01..06/08/13/16). Same fake/spy style as `KeepAwakeModelTests`; the helper
/// service and power-source monitor are fakes, so no SMAppService/XPC/IOPS is touched.
@MainActor
final class KeepAwakeModelLidCloseTests: XCTestCase {

    // MARK: - Fakes

    private final class FakeSleepAssertionService: SleepAssertionControlling {
        func activate() -> Bool { true }
        func deactivate() {}
    }

    /// Spy for the helper seam. `callLog` keeps the global call order so serialization
    /// is provable; `activate()` suspends once so rapid toggles get a real chance to
    /// interleave if transitions were not serialized.
    private final class FakeLidCloseService: LidCloseSleepControlling {
        var activateOutcome: LidCloseActivationOutcome = .active
        private(set) var callLog: [String] = []

        var activateCalls: Int { callLog.filter { $0 == "activate" }.count }
        var deactivateCalls: Int { callLog.filter { $0 == "deactivate" }.count }

        func activate() async -> LidCloseActivationOutcome {
            callLog.append("activate")
            await Task.yield()
            return activateOutcome
        }

        func deactivate() async {
            callLog.append("deactivate")
        }
    }

    private final class FakePowerSourceMonitor: PowerSourceMonitoring {
        var onChange: ((PowerSourceSnapshot) -> Void)?
        /// Delivered synchronously on `start()`, mirroring the real monitor's
        /// immediate first collect.
        var snapshotOnStart: PowerSourceSnapshot?
        private(set) var startCalls = 0
        private(set) var stopCalls = 0
        var isRunning: Bool { startCalls > stopCalls }

        func start() {
            startCalls += 1
            if let snapshotOnStart { onChange?(snapshotOnStart) }
        }

        func stop() {
            stopCalls += 1
        }

        func emit(_ snapshot: PowerSourceSnapshot) {
            onChange?(snapshot)
        }
    }

    // MARK: - Helpers

    private func makeModel(
        keepAwakeOn: Bool = true,
        defaults: UserDefaults? = nil,
        helper: FakeLidCloseService? = nil,
        monitor: FakePowerSourceMonitor? = nil
    ) -> (KeepAwakeModel, FakeLidCloseService, FakePowerSourceMonitor) {
        let helper = helper ?? FakeLidCloseService()
        let monitor = monitor ?? FakePowerSourceMonitor()
        let model = KeepAwakeModel(
            userDefaults: defaults ?? freshDefaults(),
            service: FakeSleepAssertionService(),
            lidCloseService: helper,
            powerSourceMonitor: monitor
        )
        if keepAwakeOn { model.setActive(true) }
        return (model, helper, monitor)
    }

    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "KeepAwakeModelLidCloseTests.\(UUID().uuidString)")!
    }

    // MARK: - LIDC-02/03: enable and disable through the helper

    // LIDC-02: enabling with an approved helper sets the flag and reports active.
    func testEnableCallsHelperOnceAndReportsActive() async {
        let (model, helper, _) = makeModel()

        await model.setLidCloseActive(true)

        XCTAssertEqual(model.lidClose, .active)
        XCTAssertEqual(helper.callLog, ["activate"])
    }

    // LIDC-03: disabling clears the flag and reports inactive.
    func testDisableCallsHelperAndReportsOff() async {
        let (model, helper, _) = makeModel()
        await model.setLidCloseActive(true)

        await model.setLidCloseActive(false)

        XCTAssertEqual(model.lidClose, .off)
        XCTAssertEqual(helper.callLog, ["activate", "deactivate"])
    }

    // MARK: - LIDC-01: reachable only while base keep-awake is on

    // LIDC-01: with base keep-awake off the sub-mode cannot be enabled — no helper call.
    func testEnableRefusedWhileBaseKeepAwakeOff() async {
        let (model, helper, _) = makeModel(keepAwakeOn: false)

        await model.setLidCloseActive(true)

        XCTAssertEqual(model.lidClose, .off)
        XCTAssertTrue(helper.callLog.isEmpty, "no helper call while base keep-awake is off")
    }

    // MARK: - LIDC-04: base off cascades sub-mode off

    // LIDC-04: turning base keep-awake off while the sub-mode is active clears the
    // flag (deactivate exactly once) and marks the sub-mode inactive.
    func testBaseOffCascadesLidCloseOff() async {
        let (model, helper, _) = makeModel()
        await model.setLidCloseActive(true)

        model.setActive(false)
        await model.settleLidCloseTransitions()

        XCTAssertFalse(model.isActive)
        XCTAssertEqual(model.lidClose, .off)
        XCTAssertEqual(helper.deactivateCalls, 1, "cascade must deactivate exactly once")
    }

    // LIDC-04 (guard): base off with the sub-mode already off makes no helper call.
    func testBaseOffWithoutLidCloseMakesNoHelperCall() async {
        let (model, helper, _) = makeModel()

        model.setActive(false)
        await model.settleLidCloseTransitions()

        XCTAssertTrue(helper.callLog.isEmpty)
    }

    // MARK: - LIDC-05/08: helper outcomes surface truthfully

    // LIDC-05: helper failure/refusal must leave the UI inactive.
    func testHelperFailureReportsOff() async {
        let helper = FakeLidCloseService()
        helper.activateOutcome = .failed
        let (model, _, _) = makeModel(helper: helper)

        await model.setLidCloseActive(true)

        XCTAssertEqual(model.lidClose, .off, "never report active without the flag set")
    }

    // LIDC-08: pending registration approval is surfaced as its own state — not active.
    func testPendingApprovalSurfacedAndNotActive() async {
        let helper = FakeLidCloseService()
        helper.activateOutcome = .pendingApproval
        let (model, _, _) = makeModel(helper: helper)

        await model.setLidCloseActive(true)

        XCTAssertEqual(model.lidClose, .pendingApproval)
    }

    // LIDC-08→10: after the user approves, a repeat enable retries the helper (pending
    // is not "already on") and goes active with no further ceremony.
    func testRepeatEnableFromPendingApprovalRetriesAndActivates() async {
        let helper = FakeLidCloseService()
        helper.activateOutcome = .pendingApproval
        let (model, _, _) = makeModel(helper: helper)
        await model.setLidCloseActive(true)

        helper.activateOutcome = .active
        await model.setLidCloseActive(true)

        XCTAssertEqual(model.lidClose, .active)
        XCTAssertEqual(helper.activateCalls, 2, "a retry from pending must reach the helper again")
    }

    // MARK: - LIDC-06: idempotent transitions

    // LIDC-06: asking for the state already in force makes no helper call.
    func testIdempotentTransitionsMakeNoHelperCall() async {
        let (model, helper, _) = makeModel()

        await model.setLidCloseActive(false) // already off — no call
        XCTAssertTrue(helper.callLog.isEmpty)

        await model.setLidCloseActive(true)
        await model.setLidCloseActive(true) // already active — no call

        XCTAssertEqual(helper.callLog, ["activate"])
        XCTAssertEqual(model.lidClose, .active)
    }

    // Edge case (spec): rapid toggles are serialized and the final state matches the
    // last requested state.
    func testRapidToggleSerializedLastRequestWins() async {
        let (model, helper, _) = makeModel()

        async let enable: Void = model.setLidCloseActive(true)
        async let disable: Void = model.setLidCloseActive(false)
        _ = await (enable, disable)

        XCTAssertEqual(model.lidClose, .off, "final state must match the last request")
        XCTAssertEqual(helper.callLog, ["activate", "deactivate"], "helper calls must be serialized in request order")
    }

    // MARK: - LIDC-13: no persistence

    // LIDC-13: the sub-mode always starts off — a new model over the same defaults
    // never restores `.active` and never touches the helper at init.
    func testSubModeStartsOffOnRelaunchDespitePriorActivation() async {
        let defaults = freshDefaults()
        let (model, _, _) = makeModel(defaults: defaults)
        await model.setLidCloseActive(true)
        XCTAssertEqual(model.lidClose, .active)

        let relaunchHelper = FakeLidCloseService()
        let (relaunched, _, _) = makeModel(keepAwakeOn: false, defaults: defaults, helper: relaunchHelper)

        XCTAssertEqual(relaunched.lidClose, .off, "sub-mode must never be restored (LIDC-13)")
        XCTAssertTrue(relaunchHelper.callLog.isEmpty, "init must not contact the helper")
        XCTAssertTrue(relaunched.isActive, "base keep-awake keeps its own restore behavior (KAWK-06)")
    }

    // LIDC-13 (storage integrity): lid-close transitions never alter the persisted
    // base keep-awake preference.
    func testLidCloseTransitionsDoNotTouchStoredBasePreference() async {
        let defaults = freshDefaults()
        let (model, _, _) = makeModel(defaults: defaults)

        await model.setLidCloseActive(true)
        await model.setLidCloseActive(false)

        XCTAssertTrue(KeepAwakeSettings.load(from: defaults).isActive, "stored base preference must be untouched")
    }

    // MARK: - LIDC-16: activation-time battery refusal

    // Edge case (spec): below 10% on battery at enable time, activation is refused —
    // no helper call, sub-mode stays off.
    func testEnableRefusedBelowThresholdOnBattery() async {
        let monitor = FakePowerSourceMonitor()
        monitor.snapshotOnStart = PowerSourceSnapshot(levelPercent: 9, isOnBattery: true)
        let (model, helper, _) = makeModel(monitor: monitor)

        await model.setLidCloseActive(true)

        XCTAssertEqual(model.lidClose, .off)
        XCTAssertTrue(helper.callLog.isEmpty, "refused activation must not reach the helper")
        XCTAssertFalse(monitor.isRunning, "monitor must not keep running after a refusal")
    }

    // LIDC-16 boundary: exactly 10% on battery allows activation.
    func testEnableAllowedAtExactly10PercentOnBattery() async {
        let monitor = FakePowerSourceMonitor()
        monitor.snapshotOnStart = PowerSourceSnapshot(levelPercent: 10, isOnBattery: true)
        let (model, _, _) = makeModel(monitor: monitor)

        await model.setLidCloseActive(true)

        XCTAssertEqual(model.lidClose, .active)
    }

    // LIDC-16: low level on AC power never refuses.
    func testEnableAllowedAt9PercentOnAC() async {
        let monitor = FakePowerSourceMonitor()
        monitor.snapshotOnStart = PowerSourceSnapshot(levelPercent: 9, isOnBattery: false)
        let (model, _, _) = makeModel(monitor: monitor)

        await model.setLidCloseActive(true)

        XCTAssertEqual(model.lidClose, .active)
    }

    // MARK: - LIDC-14/15: battery fail-safe while active

    // LIDC-14: a reading below 10% on battery while active deactivates the sub-mode —
    // helper deactivate called exactly once even when readings repeat.
    func testFailsafeSnapshotDeactivatesSubModeExactlyOnce() async {
        let monitor = FakePowerSourceMonitor()
        let (model, helper, _) = makeModel(monitor: monitor)
        await model.setLidCloseActive(true)

        monitor.emit(PowerSourceSnapshot(levelPercent: 9, isOnBattery: true))
        monitor.emit(PowerSourceSnapshot(levelPercent: 8, isOnBattery: true))
        await model.settleLidCloseTransitions()

        XCTAssertEqual(model.lidClose, .off)
        XCTAssertEqual(helper.deactivateCalls, 1, "repeated qualifying readings must deactivate exactly once")
        XCTAssertFalse(monitor.isRunning, "monitor must stop once the sub-mode is off")
    }

    // LIDC-14 (branch): non-qualifying readings while active change nothing.
    func testHealthySnapshotsKeepSubModeActive() async {
        let monitor = FakePowerSourceMonitor()
        let (model, helper, _) = makeModel(monitor: monitor)
        await model.setLidCloseActive(true)

        monitor.emit(PowerSourceSnapshot(levelPercent: 50, isOnBattery: true))
        monitor.emit(PowerSourceSnapshot(levelPercent: 9, isOnBattery: false))
        await model.settleLidCloseTransitions()

        XCTAssertEqual(model.lidClose, .active)
        XCTAssertEqual(helper.callLog, ["activate"], "healthy readings must not reach the helper")
    }

    // LIDC-15: after the fail-safe fires, reconnecting external power must NOT
    // re-enable the sub-mode — it stays off until the user re-enables it manually.
    func testNoAutoRearmOnPowerReconnect() async {
        let monitor = FakePowerSourceMonitor()
        let (model, helper, _) = makeModel(monitor: monitor)
        await model.setLidCloseActive(true)
        monitor.emit(PowerSourceSnapshot(levelPercent: 9, isOnBattery: true))
        await model.settleLidCloseTransitions()

        monitor.emit(PowerSourceSnapshot(levelPercent: 9, isOnBattery: false))
        await model.settleLidCloseTransitions()

        XCTAssertEqual(model.lidClose, .off, "power reconnect must not re-arm the sub-mode")
        XCTAssertEqual(helper.activateCalls, 1, "no helper activation without a manual re-enable")
    }

    // LIDC-16: the fail-safe deactivates only the sub-mode; base keep-awake stays in
    // its current state.
    func testFailsafeLeavesBaseKeepAwakeUntouched() async {
        let monitor = FakePowerSourceMonitor()
        let (model, _, _) = makeModel(monitor: monitor)
        await model.setLidCloseActive(true)

        monitor.emit(PowerSourceSnapshot(levelPercent: 9, isOnBattery: true))
        await model.settleLidCloseTransitions()

        XCTAssertTrue(model.isActive, "base keep-awake must survive the fail-safe")
        XCTAssertEqual(model.lidClose, .off)
    }

    // Fail-safe scoping: the power-source monitor runs only while the sub-mode is
    // active — never before the first enable and not after a manual disable.
    func testMonitorObservedOnlyWhileSubModeActive() async {
        let monitor = FakePowerSourceMonitor()
        let (model, _, _) = makeModel(monitor: monitor)
        XCTAssertEqual(monitor.startCalls, 0, "monitor must not run before the sub-mode is enabled")

        await model.setLidCloseActive(true)
        XCTAssertTrue(monitor.isRunning, "monitor must run while the sub-mode is active")

        await model.setLidCloseActive(false)
        XCTAssertFalse(monitor.isRunning, "monitor must stop with the sub-mode")
    }
}
