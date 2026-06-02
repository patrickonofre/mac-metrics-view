import XCTest
@testable import MacMetricsView

/// Fake probe so tests drive the recovery flow without spawning a real process.
/// Completions fire synchronously on the main actor by default, which keeps the
/// `CPUState` poll-loop tests deterministic; `defersCompletion` lets a test hold a
/// result back to simulate one arriving after recovery was cancelled.
@MainActor
final class FakeAccessibilityProbe: AccessibilityProbing {
    var result: Bool
    private(set) var probeCallCount = 0
    var defersCompletion = false
    private var pending: [@MainActor (Bool) -> Void] = []

    init(result: Bool = false) {
        self.result = result
    }

    func probe(completion: @escaping @MainActor (Bool) -> Void) {
        probeCallCount += 1
        if defersCompletion {
            pending.append(completion)
        } else {
            completion(result)
        }
    }

    /// Invokes any held-back completions with the current `result`.
    func flush() {
        let calls = pending
        pending.removeAll()
        for call in calls { call(result) }
    }
}

@MainActor
final class AccessibilityProbeTests: XCTestCase {

    // MARK: - Flag + exit-code contract (the testable entry-path helper)

    func testProbeFlagDetectedInArguments() {
        XCTAssertTrue(AccessibilityProbeFlag.isProbeMode(arguments: ["MacMetricsView", "--ax-probe"]))
    }

    func testProbeFlagAbsentMeansNormalLaunch() {
        XCTAssertFalse(AccessibilityProbeFlag.isProbeMode(arguments: ["MacMetricsView"]))
    }

    func testExitCodeEncodesTrustedAsZero() {
        XCTAssertEqual(AccessibilityProbeFlag.exitCode(isTrusted: true), 0)
    }

    func testExitCodeEncodesUntrustedAsOne() {
        XCTAssertEqual(AccessibilityProbeFlag.exitCode(isTrusted: false), 1)
    }

    func testTrustedDecodingRoundTrips() {
        XCTAssertTrue(AccessibilityProbeFlag.isTrusted(exitStatus: AccessibilityProbeFlag.exitCode(isTrusted: true)))
        XCTAssertFalse(AccessibilityProbeFlag.isTrusted(exitStatus: AccessibilityProbeFlag.exitCode(isTrusted: false)))
    }

    func testNonZeroExitStatusIsNotTrusted() {
        // Crashes/signals (e.g. status 139) must never read as trusted.
        XCTAssertFalse(AccessibilityProbeFlag.isTrusted(exitStatus: 139))
    }

    // MARK: - System probe: exit-code → Bool mapping
    //
    // Spawns trivial system binaries instead of re-running the test host with
    // `--ax-probe` (which would recurse), exercising the real Process lifecycle and
    // the exit-status mapping without touching real Accessibility state.

    func testSystemProbeMapsZeroExitToTrusted() async {
        let probe = SystemAccessibilityProbe(executableURL: URL(fileURLWithPath: "/usr/bin/true"), arguments: [])
        let result = await runProbe(probe)
        XCTAssertTrue(result)
    }

    func testSystemProbeMapsNonZeroExitToUntrusted() async {
        let probe = SystemAccessibilityProbe(executableURL: URL(fileURLWithPath: "/usr/bin/false"), arguments: [])
        let result = await runProbe(probe)
        XCTAssertFalse(result)
    }

    func testSystemProbeFailsToLaunchReportsUntrusted() async {
        let probe = SystemAccessibilityProbe(
            executableURL: URL(fileURLWithPath: "/nonexistent/mac-metrics-view-probe"),
            arguments: []
        )
        let result = await runProbe(probe)
        XCTAssertFalse(result)
    }

    func testSystemProbeWithNoExecutableReportsUntrusted() async {
        let probe = SystemAccessibilityProbe(executableURL: nil)
        let result = await runProbe(probe)
        XCTAssertFalse(result)
    }

    func testSystemProbeCompletionDeliveredOnMainActor() async {
        let probe = SystemAccessibilityProbe(executableURL: URL(fileURLWithPath: "/usr/bin/true"), arguments: [])
        let onMain: Bool = await withCheckedContinuation { continuation in
            probe.probe { _ in continuation.resume(returning: Thread.isMainThread) }
        }
        XCTAssertTrue(onMain)
    }

    // MARK: - Fake probe

    func testFakeProbeReturnsPresetResultAndRecordsInvocation() {
        let probe = FakeAccessibilityProbe(result: true)
        var received: Bool?
        probe.probe { received = $0 }
        XCTAssertEqual(received, true)
        XCTAssertEqual(probe.probeCallCount, 1)
    }

    func testFakeProbeDefersCompletionUntilFlushed() {
        let probe = FakeAccessibilityProbe(result: true)
        probe.defersCompletion = true
        var received: Bool?
        probe.probe { received = $0 }
        XCTAssertNil(received)
        probe.flush()
        XCTAssertEqual(received, true)
    }

    // MARK: - Helpers

    private func runProbe(_ probe: SystemAccessibilityProbe) async -> Bool {
        await withCheckedContinuation { continuation in
            probe.probe { continuation.resume(returning: $0) }
        }
    }
}
