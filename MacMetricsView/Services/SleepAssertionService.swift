import Foundation
import IOKit.pwr_mgt

/// Creates and releases a power-management assertion that keeps the Mac awake. The only
/// code touching `IOPMAssertion` (Reader/Service convention). Prevents both display and
/// system idle sleep via `PreventUserIdleDisplaySleep` (KAWK-01). No entitlement, no
/// network. Injectable so `KeepAwakeModel` is unit-testable without touching IOKit.
protocol SleepAssertionControlling: AnyObject {
    /// Creates the assertion if not already held. Returns whether keep-awake is active
    /// afterwards — `false` means the OS refused (KAWK-02). Idempotent: a second call
    /// while already held is a no-op that returns `true` (KAWK-04).
    func activate() -> Bool
    /// Releases the assertion if held. No-op otherwise.
    func deactivate()
}

/// `SleepAssertionControlling` backed by IOKit power management. Holds at most one
/// assertion ID at a time; the assertion also dies automatically when the process exits,
/// so a keep-awake left on can never outlive the app.
final class IOPMSleepAssertionService: SleepAssertionControlling {
    /// The IOKit assertion type string. `kIOPMAssertionTypePreventUserIdleDisplaySleep`
    /// is a `CFSTR()` macro, which Swift does not import, so the literal value is used.
    private static let assertionType = "PreventUserIdleDisplaySleep"
    private static let assertionName = "Mac Metrics View keep awake"

    private var assertionID: IOPMAssertionID?

    func activate() -> Bool {
        if assertionID != nil { return true }

        var id: IOPMAssertionID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            Self.assertionType as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            Self.assertionName as CFString,
            &id
        )
        guard result == kIOReturnSuccess else { return false }
        assertionID = id
        return true
    }

    func deactivate() {
        guard let id = assertionID else { return }
        IOPMAssertionRelease(id)
        assertionID = nil
    }
}
