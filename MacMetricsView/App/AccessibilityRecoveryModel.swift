import Foundation
import Combine

/// Where the cleaning-permission recovery flow is, for the UI to render and for the
/// state machine to gate its probe poll loop and one-shot relaunch (see ADR-002).
enum AccessibilityRecoveryPhase: Equatable {
    /// Not recovering — no probing happens.
    case idle
    /// Settings opened; the probe poll loop is running, watching for a valid grant.
    case awaitingGrant
    /// A valid grant was detected; the relaunch that applies it is in flight.
    case applying
}

/// The Accessibility (AX) self-healing recovery sub-component of the Utilities pillar
/// (TD-012): tracks the live AX grant gating the cleaning lock, detects an update-reset
/// grant (ad-hoc signing, TD-010), and drives the recovery state machine (open Settings,
/// poll for the re-added grant, relaunch once trusted). Extracted from `CPUState`
/// (spec `spec-cpustate-pillar-decouple`, task-004). Composed inside `CleaningLockModel`,
/// which bridges this model's `objectWillChange` into its own (nested `ObservableObject`s
/// do not propagate through SwiftUI containment).
///
/// **Passive by design** (feature `cleaning-lock-opt-in`, CLNGT-01): `init` performs no
/// AX check, no tracker write, and no side effect of any kind — it only loads the
/// trackers already on disk. The very first `evaluate()` happens only when a caller
/// explicitly invokes `refreshAuthorization()`/`beginRecovery()`/`evaluateLaunchNudge()`.
/// `CleaningLockModel` (the owner) decides whether and when that first call happens,
/// gated by `CleaningLockSettings.isEnabled` — so a user who never enables the
/// cleaning-lock feature never triggers `AXIsProcessTrusted()` or a grant-tracker write.
@MainActor
final class AccessibilityRecoveryModel: ObservableObject {
    /// Live Accessibility permission gate for the cleaning lock. Refreshed on each
    /// popover show so a grant made in System Settings is reflected without relaunching.
    @Published private(set) var isGranted: Bool = false
    /// True when AX is not currently granted but a *previous* app version had it — i.e.
    /// an update reset the permission (ad-hoc signing, TD-010). The UI uses this to tell
    /// the user the stale System Settings entry must be removed and re-added.
    @Published private(set) var resetByUpdate: Bool = false
    /// Where the self-healing recovery flow is. Drives the popover's recovery card
    /// (awaiting vs applying) and gates the probe poll loop: probing happens only
    /// while `.awaitingGrant`.
    @Published private(set) var phase: AccessibilityRecoveryPhase = .idle

    /// Called when the user asks to relaunch after granting Accessibility; `AppDelegate`
    /// owns the relaunch.
    var onRelaunch: (() -> Void)?
    /// Asks the UI to open the popover programmatically (for the one-time post-update
    /// nudge). `AppDelegate` wires this to `StatusItemController.openPopover()`.
    var onRequestOpenPopover: (() -> Void)?

    private let userDefaults: UserDefaults
    private let authorization: AccessibilityAuthorizationProtocol
    private let probe: AccessibilityProbing
    private let currentAppVersion: String
    private var grantTracker: AccessibilityGrantTracker
    /// One-time auto-open nudge persistence (fires once per reset event).
    private var nudgeTracker: AccessibilityNudgeTracker
    /// Snapshot of the tracker as it was *before this launch* recorded the current
    /// version. Reset detection is computed against this frozen baseline so the flag
    /// stays stable across in-session refreshes — once the current version is recorded
    /// as "seen", the live tracker would no longer report a reset, but the user still
    /// needs the recovery guidance until they grant.
    private let resetBaselineTracker: AccessibilityGrantTracker
    /// Active only while `phase == .awaitingGrant`; spawns a probe each tick.
    private var pollTimer: Timer?
    /// Probe cadence during recovery. Slow enough to stay cheap (a process spawn per
    /// tick), fast enough that re-adding the entry is noticed promptly.
    private let pollInterval: TimeInterval = 1.5
    /// True once the native AX prompt has been shown this session. macOS only surfaces
    /// that prompt once per launch, so later taps fall back to opening the Settings pane
    /// directly instead of doing nothing.
    private var hasPromptedForAccess = false

    init(
        userDefaults: UserDefaults,
        authorization: AccessibilityAuthorizationProtocol,
        probe: AccessibilityProbing,
        currentAppVersion: String
    ) {
        self.userDefaults = userDefaults
        self.authorization = authorization
        self.probe = probe
        self.currentAppVersion = currentAppVersion
        let loadedTracker = AccessibilityGrantTracker.load(from: userDefaults)
        grantTracker = loadedTracker
        resetBaselineTracker = loadedTracker
        nudgeTracker = AccessibilityNudgeTracker.load(from: userDefaults)
    }

    deinit {
        pollTimer?.invalidate()
    }

    /// Re-reads the live Accessibility permission and republishes it so the cleaning-lock
    /// UI reflects a grant made in System Settings without an app relaunch. Called
    /// whenever the popover is shown.
    func refreshAuthorization() {
        evaluate()
    }

    /// User-initiated request for the Accessibility grant. The first tap shows the
    /// native macOS prompt (which registers the entry under the running build's
    /// identity); later taps open the Settings pane directly, since the system prompt
    /// only appears once per launch.
    func requestAccess() {
        if hasPromptedForAccess {
            authorization.openSettings()
        } else {
            hasPromptedForAccess = true
            authorization.promptForAccess()
            authorization.openSettings()
        }
    }

    /// Starts active recovery: opens the Accessibility pane and begins polling a fresh
    /// child-process probe for the *current* code identity's grant (the in-process
    /// `AXIsProcessTrusted()` stays stale, ADR-002). On the first trusted result the app
    /// relaunches to apply the grant.
    func beginRecovery() {
        guard phase == .idle else { return }
        phase = .awaitingGrant
        // Reuses the request path: the first call shows the native prompt, which
        // registers the entry under the *running build's* identity (avoiding the
        // stale-entry trap), and opens the Accessibility pane. Later calls just open
        // Settings. The probe loop then watches for the re-added grant.
        requestAccess()
        startPolling()
    }

    /// Stops active recovery (e.g. the popover was dismissed before a grant) and tears
    /// down the poll loop, returning to `.idle`.
    func cancelRecovery() {
        guard phase == .awaitingGrant else { return }
        stopPolling()
        phase = .idle
    }

    /// One poll tick: spawn a fresh probe and apply its result. Not private so unit
    /// tests can drive ticks deterministically. A no-op outside active recovery, so a
    /// late timer fire after cancel cannot spawn a probe.
    func pollRecovery() {
        guard phase == .awaitingGrant else { return }
        probe.probe { [weak self] trusted in
            self?.handleProbeResult(trusted)
        }
    }

    /// One-time launch decision: when an update reset the grant and the proactive nudge
    /// has not yet fired for this version, ask the UI to open the recovery card once,
    /// recording the nudge so it never repeats for this version (ADR-003).
    func evaluateLaunchNudge() {
        guard !isGranted else { return }
        guard resetByUpdate else { return }
        guard nudgeTracker.shouldNudge(forVersion: currentAppVersion) else { return }
        nudgeTracker = nudgeTracker.recordingNudge(version: currentAppVersion)
        nudgeTracker.save(to: userDefaults)
        onRequestOpenPopover?()
    }

    private func handleProbeResult(_ trusted: Bool) {
        // Ignore a result that lands after cancel or after applying already began —
        // relaunch fires at most once, only during active recovery.
        guard phase == .awaitingGrant, trusted else { return }
        phase = .applying
        stopPolling()
        onRelaunch?()
    }

    private func startPolling() {
        stopPolling()
        pollTimer = MainRunLoopTimer.repeating(every: pollInterval) { [weak self] in
            self?.pollRecovery()
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Reads the live AX permission, publishes the gate, and maintains the grant
    /// tracker so an update-reset state can be told apart from a normal first-time
    /// grant. When trusted, records the current version as the last granted one; when
    /// not, flags whether an earlier version had been granted.
    private func evaluate() {
        let trusted = authorization.isTrusted
        isGranted = trusted

        if trusted {
            resetByUpdate = false
            if grantTracker.lastGrantedVersion != currentAppVersion {
                grantTracker = grantTracker.recordingGrant(version: currentAppVersion)
                grantTracker.save(to: userDefaults)
            }
        } else {
            // Compare against the pre-launch baseline so the flag does not flip off
            // once this version is recorded as seen below.
            resetByUpdate = resetBaselineTracker.wasResetByUpdate(
                isTrusted: false,
                currentVersion: currentAppVersion
            )
            // Remember that this build ran (even ungranted), so a *future* update can
            // be recognised as a reset for never-granted users too.
            if grantTracker.lastSeenVersion != currentAppVersion {
                grantTracker = grantTracker.recordingSeen(version: currentAppVersion)
                grantTracker.save(to: userDefaults)
            }
        }
    }
}
