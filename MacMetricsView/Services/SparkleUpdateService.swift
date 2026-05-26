#if canImport(Sparkle)
import Sparkle

/// Sparkle-backed updater. Compiled only when `Sparkle.framework` is embedded in
/// the Xcode-built `.app`; the entire body is gated by `#if canImport(Sparkle)`
/// so the SPM build never references Sparkle. Configuration (feed URL, public
/// EdDSA key, automatic-check default, profiling off) comes from `Info.plist`.
///
/// Subclasses `NSObject` because `SPUUpdaterDelegate` inherits from
/// `NSObjectProtocol`. The delegate is wired before the updater starts so the
/// passive probe's callbacks are never missed.
@MainActor
final class SparkleUpdateService: NSObject, AppUpdateService, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController!

    var onAvailableVersionChange: ((String?) -> Void)?

    override init() {
        super.init()
        // Build the controller after super.init so `self` can be the delegate,
        // and start it manually so the delegate is wired before any check runs.
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        controller.startUpdater()
    }

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }

    func probeForUpdateInformation() {
        controller.updater.checkForUpdateInformation()
    }

    // MARK: - SPUUpdaterDelegate

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString ?? item.versionString
        onAvailableVersionChange?(version.isEmpty ? nil : version)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        onAvailableVersionChange?(nil)
    }
}
#endif
