#if canImport(Sparkle)
import Sparkle

/// Sparkle-backed updater. Compiled only when `Sparkle.framework` is embedded in
/// the Xcode-built `.app`; the entire body is gated by `#if canImport(Sparkle)`
/// so the SPM build never references Sparkle. Configuration (feed URL, public
/// EdDSA key, automatic-check default, profiling off) comes from `Info.plist`.
@MainActor
final class SparkleUpdateService: AppUpdateService {
    private let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }

    func setAutomaticChecks(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
    }
}
#endif
