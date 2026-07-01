import AppKit
import SwiftUI

// MARK: - Window

/// Borderless, opaque window that sits above everything (including full-screen
/// apps) on one screen. Created once per connected display by `LockOverlayController`.
private final class LockOverlayWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        // screenSaverWindowLevel covers full-screen spaces and Dock.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = true
        hasShadow = false
        isMovable = false
        backgroundColor = .black
        // The CGEventTap already swallows all input; the window itself should
        // not become the first responder so the menu bar stays unaffected.
        isReleasedWhenClosed = false
    }
}

// MARK: - Controller

/// Manages one `LockOverlayWindow` per connected screen.
/// Call `show(state:)` when a lock session starts and `hide()` when it ends.
@MainActor
final class LockOverlayController {
    private var windows: [LockOverlayWindow] = []
    private var screenObserver: NSObjectProtocol?

    func show(lock: CleaningLockModel) {
        createWindows(for: lock)
        startObservingScreenChanges(lock: lock)
    }

    func hide() {
        windows.forEach { $0.orderOut(nil) }
        windows = []
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
            screenObserver = nil
        }
    }

    // MARK: - Private

    private func createWindows(for lock: CleaningLockModel) {
        // Tear down any existing windows before rebuilding (handles screen-config changes).
        windows.forEach { $0.orderOut(nil) }
        windows = NSScreen.screens.map { screen in
            let window = LockOverlayWindow(screen: screen)
            window.contentView = NSHostingView(rootView: LockOverlayView(lock: lock))
            window.orderFrontRegardless()
            return window
        }
    }

    private func startObservingScreenChanges(lock: CleaningLockModel) {
        if let existing = screenObserver {
            NotificationCenter.default.removeObserver(existing)
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.createWindows(for: lock)
            }
        }
    }
}
