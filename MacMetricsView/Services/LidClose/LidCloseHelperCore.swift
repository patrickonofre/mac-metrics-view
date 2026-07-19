import Foundation

/// Pure command→action core of the privileged `MacMetricsHelper` daemon (feature
/// `lid-close-keep-awake`). The daemon's `main.swift` (xcodeproj-only) wires an
/// NSXPCListener to this class with a real `/usr/bin/pmset -a disablesleep` runner;
/// compiling the core in the app's SwiftPM target keeps all daemon logic under
/// `swift test` via the injected `runPmset` seam.
final class LidCloseHelperCore {
    /// Runs `pmset -a disablesleep <1|0>`; returns whether the command succeeded.
    private let runPmset: (Bool) -> Bool

    /// Whether the sleep-disabled flag is currently believed set by this helper. Only
    /// successful pmset runs mutate it, so a refused enable never arms the
    /// connection-loss revert.
    private(set) var isEnabled = false

    init(runPmset: @escaping (Bool) -> Bool) {
        self.runPmset = runPmset
    }

    /// Applies the requested flag state (LIDC-02 enable, LIDC-03 disable). Returns
    /// whether pmset succeeded — `false` travels back over XPC and surfaces as
    /// LIDC-05 in the app.
    func setSleepDisabled(_ disabled: Bool) -> Bool {
        guard runPmset(disabled) else { return false }
        isEnabled = disabled
        return true
    }

    /// App connection lost (crash, force-kill, quit without deactivate): revert the
    /// flag to `false` exactly once iff currently enabled (LIDC-12). State clears
    /// after the single attempt — the client is gone, so there is nothing to retry
    /// for; reboot clears the flag as the last-ditch backstop (pmset semantics).
    func connectionLost() {
        guard isEnabled else { return }
        isEnabled = false
        _ = runPmset(false)
    }
}
