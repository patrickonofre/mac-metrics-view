import Foundation
import Combine

enum LaunchAtLoginStatus: Equatable {
    case enabled
    case disabled
    case unavailable
    case error

    var localizedName: String {
        switch self {
        case .enabled:
            return "Ativado"
        case .disabled:
            return "Desativado"
        case .unavailable:
            return "Indisponível"
        case .error:
            return "Erro"
        }
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
