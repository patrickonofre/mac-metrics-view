import Foundation

/// Entry point of the privileged `MacMetricsHelper` launchd daemon (feature
/// `lid-close-keep-awake`). Deliberately thin: every decision lives in
/// `LidCloseHelperCore` (compiled into both this target and the app's SwiftPM
/// target, where `swift test` covers it); this file only wires the XPC listener,
/// the real pmset runner, and client code-signing validation.
///
/// xcodeproj-only — not part of Package.swift (the SwiftPM build has no daemon).

/// Serializes every touch of `core`: XPC delivers each connection's messages and
/// invalidation handlers on their own queues, so a shared serial queue keeps the
/// core's enabled-state transitions ordered (enable → connection lost → revert).
let helperQueue = DispatchQueue(label: "com.patrickonofre.MacMetricsView.helper.core")

/// Real pmset runner (LIDC-02/03): absolute path, exit-code checked. A non-zero
/// exit or spawn failure reports `false`, which travels back over XPC and surfaces
/// as LIDC-05 in the app (never "active" without the flag actually set).
let core = LidCloseHelperCore { disabled in
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    process.arguments = ["-a", "disablesleep", disabled ? "1" : "0"]
    do {
        try process.run()
    } catch {
        return false
    }
    process.waitUntilExit()
    return process.terminationStatus == 0
}

/// XPC-facing wrapper: hops onto `helperQueue` and delegates to the tested core.
final class ExportedHelper: NSObject, LidCloseHelperProtocol {
    func setSleepDisabled(_ disabled: Bool, reply: @escaping (Bool) -> Void) {
        helperQueue.async {
            reply(core.setSleepDisabled(disabled))
        }
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    /// Client validation (LIDC-10 security boundary), mirroring the app side's
    /// requirement on this daemon (see `HelperLidCloseSleepService`): the connecting
    /// process must be the Mac Metrics View app — bundle identifier
    /// `com.pso.MacMetricsView` — signed with the repo's self-signed certificate
    /// (leaf subject CN "Mac Metrics View Self-Signed", scripts/create-signing-cert.sh).
    /// CN matching over leaf-hash pinning is a deliberate self-signed-distribution
    /// tradeoff documented on the app side.
    static let clientCodeSigningRequirement =
        #"identifier "com.pso.MacMetricsView" and certificate leaf[subject.CN] = "Mac Metrics View Self-Signed""#

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        do {
            try newConnection.setCodeSigningRequirement(Self.clientCodeSigningRequirement)
        } catch {
            // Requirement string failed to parse/apply — refuse everything rather
            // than run a root service without client validation.
            return false
        }

        newConnection.exportedInterface = NSXPCInterface(with: LidCloseHelperProtocol.self)
        newConnection.exportedObject = ExportedHelper()

        // Orphan guarantee (LIDC-12): losing the app connection — crash, force-kill,
        // or quit — reverts the flag iff currently enabled (core decides, tested).
        let onConnectionLost = {
            helperQueue.async { core.connectionLost() }
        }
        newConnection.invalidationHandler = onConnectionLost
        newConnection.interruptionHandler = onConnectionLost

        newConnection.resume()
        return true
    }
}

let delegate = ListenerDelegate()
let listener = NSXPCListener(machServiceName: LidCloseHelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
