import Foundation
import ServiceManagement

/// Control seam for the lid-close sleep-disabled flag. The concrete implementation
/// talks to the privileged helper daemon; `KeepAwakeModel` tests inject a fake
/// (same injection idiom as `SleepAssertionControlling`). Main-actor bound (like
/// `PowerSourceMonitoring`): `KeepAwakeModel` owns it and `onConnectionLost` mutates
/// main-actor UI state.
@MainActor
protocol LidCloseSleepControlling: AnyObject {
    /// Registers the helper if needed and asks it to set the sleep-disabled flag.
    /// `.pendingApproval` means the daemon awaits user approval in System Settings →
    /// Login Items (LIDC-08); `.failed` means registration or the XPC call was
    /// refused (LIDC-05/09) — the sub-mode must show inactive.
    func activate() async -> LidCloseActivationOutcome
    /// Asks the helper to clear the flag and drops the XPC connection. Safe to call
    /// when nothing was ever activated.
    func deactivate() async
    /// Fired when a live helper connection drops without `deactivate()` (daemon
    /// crash/restart). A fresh daemon no longer tracks the flag, so the model must
    /// stop claiming it (LIDC-05 direction: fail toward "off").
    var onConnectionLost: (() -> Void)? { get set }
}

/// `LidCloseSleepControlling` backed by `SMAppService` + XPC. The only app-side code
/// touching `ServiceManagement` (thin-service convention of `IOPMSleepAssertionService`).
///
/// Orphan guarantee (LIDC-11/12): the XPC connection stays alive exactly while the
/// sub-mode is active. The root daemon reverts the flag in its connection-loss
/// handler, so app crash/force-kill restores normal sleep; `deactivate()` covers the
/// cooperative path and then tears the connection down.
@MainActor
final class HelperLidCloseSleepService: LidCloseSleepControlling {

    /// Code-signing requirement applied to the helper connection. Decision: match the
    /// helper's signing identifier plus the *subject CN* of the self-signed leaf
    /// certificate ("Mac Metrics View Self-Signed", see scripts/create-signing-cert.sh),
    /// NOT the leaf hash. Rationale: the repo's cert is self-signed, so there is no
    /// Apple anchor to pin; pinning the leaf hash (`certificate leaf = H"..."`) would
    /// hard-code one keychain's cert into the binary and break on cert regeneration or
    /// other dev machines. CN matching is forgeable by a local actor minting a same-CN
    /// cert — an accepted limit of self-signed distribution (memory: free signing
    /// preferred): anyone able to plant a root daemon or re-sign binaries already owns
    /// the machine. launchd additionally guarantees this mach service name resolves to
    /// the registered daemon. The helper applies the mirrored requirement (app bundle
    /// id `com.pso.MacMetricsView`, same CN) to its clients.
    static let helperCodeSigningRequirement =
        #"identifier "com.patrickonofre.MacMetricsView.helper" and certificate leaf[subject.CN] = "Mac Metrics View Self-Signed""#

    private var connection: NSXPCConnection?

    var onConnectionLost: (() -> Void)?

    nonisolated init() {}

    // MARK: - LidCloseSleepControlling

    func activate() async -> LidCloseActivationOutcome {
        let daemon = SMAppService.daemon(plistName: LidCloseHelperConstants.plistName)

        if daemon.status != .enabled {
            // First activation registers the daemon (LIDC-07, at most one admin
            // approval ever). `register()` throws when approval is pending or refused;
            // the post-attempt status disambiguates the two.
            try? daemon.register()
            switch daemon.status {
            case .enabled:
                break
            case .requiresApproval:
                return .pendingApproval
            default:
                return .failed
            }
        }

        let applied = await sendSetSleepDisabled(true)
        if !applied {
            // Never report active without the flag set (LIDC-05); drop the dead/broken
            // connection so a retry starts clean.
            tearDownConnection()
            return .failed
        }
        return .active
    }

    func deactivate() async {
        // No live connection ⇒ nothing was activated through this service; creating
        // one here would needlessly launch the daemon.
        guard connection != nil else { return }
        _ = await sendSetSleepDisabled(false)
        tearDownConnection()
    }

    /// Deep-link to System Settings → Login Items for the pending-approval card (LIDC-08).
    static func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: - XPC plumbing

    private func sendSetSleepDisabled(_ disabled: Bool) async -> Bool {
        let connection = ensureConnection()
        let resumeOnce = ResumeOnce()
        return await withCheckedContinuation { continuation in
            // XPC invokes either the error handler or the reply; the claim guard makes
            // the continuation single-resume even if that contract is ever violated.
            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
                if resumeOnce.claim() { continuation.resume(returning: false) }
            }
            guard let helper = proxy as? LidCloseHelperProtocol else {
                if resumeOnce.claim() { continuation.resume(returning: false) }
                return
            }
            helper.setSleepDisabled(disabled) { applied in
                if resumeOnce.claim() { continuation.resume(returning: applied) }
            }
        }
    }

    private func ensureConnection() -> NSXPCConnection {
        if let connection { return connection }

        // `.privileged` targets the launchd-managed root daemon's mach service.
        let new = NSXPCConnection(
            machServiceName: LidCloseHelperConstants.machServiceName,
            options: .privileged
        )
        new.remoteObjectInterface = NSXPCInterface(with: LidCloseHelperProtocol.self)
        new.setCodeSigningRequirement(Self.helperCodeSigningRequirement)
        // Both handlers funnel into the same loss path: interruption is the daemon
        // process dying (launchd may respawn it with no flag state), invalidation is
        // the connection going away entirely. `tearDownConnection` nils `connection`
        // first, so a deliberate teardown never reports a loss.
        // Captured as an identity token: the handler only needs to know *which*
        // connection died, and NSXPCConnection is not Sendable.
        let lostToken = ObjectIdentifier(new)
        let reportLoss: @Sendable () -> Void = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.connection.map(ObjectIdentifier.init) == lostToken else { return }
                self.connection = nil
                self.onConnectionLost?()
            }
        }
        new.invalidationHandler = reportLoss
        new.interruptionHandler = reportLoss
        new.resume()
        connection = new
        return new
    }

    private func tearDownConnection() {
        let current = connection
        connection = nil
        current?.invalidate()
    }
}

/// Lock-guarded once-flag so an XPC reply and error handler can never double-resume
/// a continuation.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}
