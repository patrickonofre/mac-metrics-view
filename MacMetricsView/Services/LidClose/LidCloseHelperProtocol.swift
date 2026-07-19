import Foundation

/// Shared XPC contract between the app and the privileged `MacMetricsHelper` daemon
/// (feature `lid-close-keep-awake`, LIDC-02). Compiled into both targets so
/// `NSXPCInterface(with:)` resolves the same protocol on each side. `@objc` because
/// NSXPCInterface requires an Objective-C-visible protocol.
@objc protocol LidCloseHelperProtocol {
    /// Sets the system-wide sleep-disabled flag (`pmset -a disablesleep`). The reply
    /// reports whether the flag was actually applied — `false` surfaces as LIDC-05
    /// (never show the sub-mode active without the flag set).
    func setSleepDisabled(_ disabled: Bool, reply: @escaping (Bool) -> Void)
}

/// Constants both sides of the XPC boundary must agree on.
enum LidCloseHelperConstants {
    /// launchd mach service name the daemon listens on and the app connects to.
    /// Must match the `MachServices` key in the helper's launchd plist.
    static let machServiceName = "com.patrickonofre.MacMetricsView.helper"
    /// Daemon plist name passed to `SMAppService.daemon(plistName:)`; the plist ships
    /// in the app bundle at `Contents/Library/LaunchDaemons/` (LIDC-07).
    static let plistName = "com.patrickonofre.MacMetricsView.helper.plist"
}
