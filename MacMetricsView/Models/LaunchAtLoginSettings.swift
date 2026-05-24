import Foundation
import Combine

enum LaunchAtLoginStatus: Equatable {
    case enabled
    case disabled
    case unavailable
    case error

    func localizedName(in language: AppLanguage = .current) -> String {
        let text: LocalizedText
        switch self {
        case .enabled:
            text = Strings.loginEnabled
        case .disabled:
            text = Strings.loginDisabled
        case .unavailable:
            text = Strings.unavailable
        case .error:
            text = Strings.loginError
        }
        return text(language)
    }
}

@MainActor
final class LaunchAtLoginSettings: ObservableObject {
    @Published private(set) var status: LaunchAtLoginStatus
    @Published private(set) var showsError = false

    private let manager: LaunchAtLoginManaging
    private let userDefaults: UserDefaults

    private enum Keys {
        static let intendedEnabled = "LaunchAtLoginSettings.intendedEnabled"
    }

    init(manager: LaunchAtLoginManaging = LaunchAtLoginManager(), userDefaults: UserDefaults = .standard) {
        self.manager = manager
        self.userDefaults = userDefaults
        status = manager.status
    }

    var isEnabled: Bool {
        status == .enabled
    }

    var isAvailable: Bool {
        status != .unavailable
    }

    func refresh() {
        status = manager.status
        showsError = false
    }

    func setEnabled(_ isEnabled: Bool) {
        userDefaults.set(isEnabled, forKey: Keys.intendedEnabled)

        do {
            try manager.setEnabled(isEnabled)
            status = manager.status
            showsError = false
        } catch {
            status = manager.status
            showsError = true
        }
    }
}
