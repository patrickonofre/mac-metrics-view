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
}
