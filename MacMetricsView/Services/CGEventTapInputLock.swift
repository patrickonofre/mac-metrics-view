import AppKit
import CoreGraphics

/// Production implementation of `InputLockServiceProtocol` backed by a
/// `CGEventTap` that consumes keyboard and pointing-device events.
///
/// **Permission required:** `AXIsProcessTrusted()` must return `true` before
/// calling `start`. Without Accessibility permission the tap cannot be
/// created and the call is a no-op.
///
/// **Escape hatch:** holding Esc for 3 continuous seconds triggers an abort.
/// That specific event is not consumed so the hold can be detected; it does
/// not propagate to other apps because the overlay covers all interaction.
///
/// **System guarantee:** the tap is torn down in `stop(reason:)`,
/// `applicationWillTerminate`, and when the process exits, so input is
/// always released.
@MainActor
final class CGEventTapInputLock: InputLockServiceProtocol {

    // MARK: - Protocol conformance

    private(set) var phase: LockPhase = .idle
    private(set) var remaining: TimeInterval = 0
    var onTick: ((TimeInterval) -> Void)?
    var onEnd: ((LockEndReason) -> Void)?

    // MARK: - Private state

    private var countdownTimer: Timer?
    private var tapPort: CFMachPort?
    private var tapRunLoopSource: CFRunLoopSource?

    /// Duration of the current session; kept to clamp `remaining`.
    private var sessionDuration: TimeInterval = 0

    // MARK: - Esc-hold abort detection

    private let abortHoldDuration: TimeInterval = 3
    private var escDownSince: Date?

    // MARK: - start / stop

    func start(duration: TimeInterval) {
        guard phase == .idle else { return }
        guard duration > 0 else { return }

        installTap()
        guard tapPort != nil else { return } // tap creation failed (no AX permission)

        sessionDuration = duration
        remaining = duration
        phase = .locked

        // Anchor to the session start (not the shared epoch grid) so the first tick fires
        // exactly 1s after the lock begins. The countdown decrements per tick, so an
        // early first tick would shorten the visible countdown by up to a second.
        countdownTimer = MainRunLoopTimer.repeating(every: 1, anchor: Date()) { [weak self] in
            self?.tick()
        }
    }

    func stop(reason: LockEndReason) {
        guard phase == .locked else { return }
        teardown()
        onEnd?(reason)
    }

    // MARK: - Countdown

    private func tick() {
        remaining = max(0, remaining - 1)
        onTick?(remaining)
        if remaining <= 0 {
            teardown()
            onEnd?(.expired)
        }
    }

    // MARK: - CGEventTap lifecycle

    private func installTap() {
        // Mask: keyboard + mouse buttons + movement + scroll + tablet gestures
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue) |
            (1 << CGEventType.mouseMoved.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.rightMouseDragged.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue)

        // Use `passUnretained` — the service outlives the tap because it is
        // owned by AppDelegate and teardown() always removes the tap first.
        let selfPtr = Unmanaged.passUnretained(self)

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo else { return Unmanaged.passRetained(event) }
                let lock = Unmanaged<CGEventTapInputLock>.fromOpaque(userInfo).takeUnretainedValue()
                return lock.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: selfPtr.toOpaque()
        ) else {
            return
        }

        tapPort = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        tapRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }

    private func teardown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        escDownSince = nil

        if let port = tapPort {
            CGEvent.tapEnable(tap: port, enable: false)
            if let source = tapRunLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
        }
        tapPort = nil
        tapRunLoopSource = nil
        remaining = 0
        phase = .idle
    }

    // MARK: - Event callback (called on main thread by CGEventTap)

    private func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {

        // Re-enable the tap if the system disabled it.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port = tapPort {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        // Esc-hold abort detection: let the key event pass so we can track it,
        // but still consume it so nothing else sees it.
        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == 53 { // kVK_Escape = 53
                if escDownSince == nil {
                    escDownSince = Date()
                } else if let since = escDownSince,
                          Date().timeIntervalSince(since) >= abortHoldDuration {
                    // Held long enough — abort.
                    // Schedule the stop on next run-loop turn to avoid
                    // re-entering the callback.
                    let selfRef = self
                    DispatchQueue.main.async {
                        selfRef.stop(reason: .aborted)
                    }
                }
                return nil // consume the Esc key
            } else {
                escDownSince = nil
            }
        }

        if type == .keyUp {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == 53 {
                escDownSince = nil
            }
        }

        // Consume all other events.
        return nil
    }
}
