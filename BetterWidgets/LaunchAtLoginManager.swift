import ServiceManagement

// The protocol keeps checks isolated from the user's real Login Items.
@MainActor
protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemService {}

@MainActor
final class LaunchAtLoginManager {
    struct ChangeResult {
        let status: SMAppService.Status
        let errorMessage: String?
    }

    private let service: any LoginItemService

    init(service: any LoginItemService = SMAppService.mainApp) {
        self.service = service
    }

    // Always ask macOS; there is no persisted preference or cached Boolean.
    func readStatus() -> SMAppService.Status {
        let status = service.status
        print("[LaunchAtLogin] status = \(statusDescription(status))")
        return status
    }

    func setEnabled(_ enabled: Bool) -> ChangeResult {
        let currentStatus = readStatus()
        if (enabled && currentStatus == .enabled) || (!enabled && currentStatus == .notRegistered) {
            return ChangeResult(status: currentStatus, errorMessage: nil)
        }

        let operation = enabled ? "register" : "unregister"
        print("[LaunchAtLogin] \(operation) requested")
        var errorMessage: String?
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            print("[LaunchAtLogin] \(operation) failed: \(error)")
            let action = enabled ? "turn on" : "turn off"
            errorMessage = "Unable to \(action) Launch at Login. \(error.localizedDescription)"
        }

        // Even a successful call can leave approval pending. An error can also
        // coincide with a system status change, so reread in both cases.
        return ChangeResult(status: readStatus(), errorMessage: errorMessage)
    }

    private func statusDescription(_ status: SMAppService.Status) -> String {
        switch status {
        case .enabled: return "enabled"
        case .notRegistered: return "notRegistered"
        case .requiresApproval: return "requiresApproval"
        case .notFound: return "notFound"
        @unknown default: return "unknown (\(status.rawValue))"
        }
    }
}
