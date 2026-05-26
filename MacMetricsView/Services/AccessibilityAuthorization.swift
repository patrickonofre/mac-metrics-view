import AppKit
import ApplicationServices

// MARK: - Protocol

/// Encapsulates Accessibility permission checks and the action that opens
/// the system panel where the user grants access.
///
/// Inject a `FakeAccessibilityAuthorization` in tests so that tests never
/// touch real macOS permission state.
protocol AccessibilityAuthorizationProtocol {
    /// Whether the app currently has Accessibility (AX) permission.
    var isTrusted: Bool { get }

    /// Opens System Settings → Privacy & Security → Accessibility.
    func openSettings()

    /// Triggers the native macOS Accessibility prompt and returns the current
    /// trust state. The prompt registers the app in the Accessibility list under
    /// the *running build's* code identity, so the entry the user then enables
    /// matches the current designated requirement (avoids the stale-entry trap).
    @discardableResult
    func promptForAccess() -> Bool
}

// MARK: - System implementation

/// Production implementation backed by `AXIsProcessTrusted()`.
final class SystemAccessibilityAuthorization: AccessibilityAuthorizationProtocol {

    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @discardableResult
    func promptForAccess() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString
        return AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }
}
