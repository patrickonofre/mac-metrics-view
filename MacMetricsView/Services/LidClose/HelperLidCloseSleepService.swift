import Foundation
import ServiceManagement

/// Control seam for the lid-close sleep-disabled flag. The concrete implementation
/// talks to the privileged helper daemon; `KeepAwakeModel` tests inject a fake
/// (same injection idiom as `SleepAssertionControlling`).
protocol LidCloseSleepControlling: AnyObject {
    /// Registers the helper if needed and asks it to set the sleep-disabled flag.
    /// `.pendingApproval` means the daemon awaits user approval in System Settings →
    /// Login Items (LIDC-08); `.failed` means registration or the XPC call was
    /// refused (LIDC-05/09) — the sub-mode must show inactive.
    func activate() async -> LidCloseActivationOutcome
    /// Asks the helper to clear the flag and drops the XPC connection. Safe to call
    /// when nothing was ever activated.
    func deactivate() async
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
        try? new.setCodeSigningRequirement(Self.helperCodeSigningRequirement)
        new.invalidationHandler = { [weak self] in
            Task { @MainActor [weak self] in
                if self?.connection === new { self?.connection = nil }
            }
        }
        new.resume()
        connection = new
        return new
    }

    private func tearDownConnection() {
        connection?.invalidate()
        connection = nil
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
