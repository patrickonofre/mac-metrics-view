import Foundation
import ServiceManagement

protocol LaunchAtLoginManaging {
    var status: LaunchAtLoginStatus { get }
    func setEnabled(_ isEnabled: Bool) throws
}

enum LaunchAtLoginError: Error {
    case unavailable
}

struct LaunchAtLoginManager: LaunchAtLoginManaging {
    var status: LaunchAtLoginStatus {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .notRegistered:
            return .disabled
        case .requiresApproval, .notFound:
            return .disabled
        @unknown default:
            return .unavailable
        }
    }

    func setEnabled(_ isEnabled: Bool) throws {
        guard status != .unavailable else {
            throw LaunchAtLoginError.unavailable
        }

        if isEnabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
