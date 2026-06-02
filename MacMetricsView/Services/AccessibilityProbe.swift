import Foundation
import ApplicationServices

// MARK: - Probe-mode flag + exit-code contract

/// The hidden launch mode and exit-code encoding shared by the entry point (which
/// runs the probe) and `SystemAccessibilityProbe` (which spawns and reads it).
///
/// A freshly spawned process escapes the per-process `AXIsProcessTrusted()` cache,
/// so its result reflects the *current* code identity's live grant — the only
/// reliable signal after the 1.4.0 signing rotation (see ADR-002).
enum AccessibilityProbeFlag {
    /// Launch argument that puts the process into probe mode.
    static let argument = "--ax-probe"

    /// Exit code the probe returns when `AXIsProcessTrusted()` is `true`.
    static let trustedExitCode: Int32 = 0
    /// Exit code the probe returns when not trusted.
    static let untrustedExitCode: Int32 = 1

    /// Whether the given launch arguments request probe mode.
    static func isProbeMode(arguments: [String]) -> Bool {
        arguments.contains(argument)
    }

    /// Encodes a freshly evaluated trust state into the exit code the parent reads.
    static func exitCode(isTrusted: Bool) -> Int32 {
        isTrusted ? trustedExitCode : untrustedExitCode
    }

    /// Decodes a child process's exit status back into a trust `Bool`. Anything
    /// other than the trusted code (including crashes/signals) is treated as
    /// "not trusted" so a malformed probe can never falsely unlock recovery.
    static func isTrusted(exitStatus: Int32) -> Bool {
        exitStatus == trustedExitCode
    }
}

// MARK: - Protocol

/// Re-evaluates the live Accessibility trust state for the app's *current* code
/// identity by spawning a fresh child process, sidestepping the per-process cache
/// of `AXIsProcessTrusted()`. Inject a fake in tests so no process spawns.
///
/// Marked `@MainActor` so the completion runs in main-actor isolation alongside
/// `CPUState`, which owns the recovery flow that consumes it.
@MainActor
protocol AccessibilityProbing {
    /// Spawns the probe and reports the freshly evaluated trust state on the main
    /// actor. Reports `false` if the probe cannot run; never throws or hangs.
    func probe(completion: @escaping @MainActor (Bool) -> Void)
}

// MARK: - System implementation

/// Production probe: re-execs the app's own binary with `--ax-probe`, waits for it
/// to exit, and maps the exit code to a trust `Bool`. The child evaluates trust and
/// exits before any UI is constructed (the entry point intercepts the flag).
///
/// `executableURL` is injectable so tests can point the spawn at a trivial binary
/// (`/usr/bin/true`, `/usr/bin/false`, or a missing path) instead of re-running the
/// test host with `--ax-probe`.
@MainActor
final class SystemAccessibilityProbe: AccessibilityProbing {

    private let executableURL: URL?
    private let arguments: [String]

    init(
        executableURL: URL? = Bundle.main.executableURL,
        arguments: [String] = [AccessibilityProbeFlag.argument]
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
    }

    func probe(completion: @escaping @MainActor (Bool) -> Void) {
        guard let executableURL else {
            // No binary to spawn — treat as not trusted.
            Task { @MainActor in completion(false) }
            return
        }

        let task = Process()
        task.executableURL = executableURL
        task.arguments = arguments
        // The probe writes its result purely through the exit code; silence any
        // incidental output so it never pollutes the parent's streams.
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        task.terminationHandler = { process in
            let trusted = AccessibilityProbeFlag.isTrusted(exitStatus: process.terminationStatus)
            // `terminationHandler` fires on an arbitrary queue; hop back to the
            // main actor so the completion runs where the caller expects.
            Task { @MainActor in completion(trusted) }
        }

        do {
            try task.run()
        } catch {
            // Launch failure (missing/invalid executable, sandbox denial): not trusted.
            Task { @MainActor in completion(false) }
        }
    }
}
