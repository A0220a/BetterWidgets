import Foundation
import ServiceManagement

@MainActor
private final class TestLoginItemService: LoginItemService {
    var status: SMAppService.Status = .notRegistered
    var statusAfterRegister: SMAppService.Status = .enabled
    var statusAfterUnregister: SMAppService.Status = .notRegistered
    var registrationError: Error?
    var unregistrationError: Error?
    private(set) var registerCalls = 0
    private(set) var unregisterCalls = 0

    func register() throws {
        registerCalls += 1
        status = statusAfterRegister
        if let registrationError { throw registrationError }
    }

    func unregister() throws {
        unregisterCalls += 1
        status = statusAfterUnregister
        if let unregistrationError { throw unregistrationError }
    }
}

@main
struct LaunchAtLoginChecks {
    @MainActor private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    @MainActor static func main() {
        let service = TestLoginItemService()
        let manager = LaunchAtLoginManager(service: service)

        require(manager.readStatus() == .notRegistered, "initial status comes from the service")
        let enabled = manager.setEnabled(true)
        require(enabled.status == .enabled && enabled.errorMessage == nil, "registration returns the actual enabled status")
        require(service.registerCalls == 1, "enabling registers once")
        _ = manager.setEnabled(true)
        require(service.registerCalls == 1, "an already enabled service is not registered twice")
        let disabled = manager.setEnabled(false)
        require(disabled.status == .notRegistered && disabled.errorMessage == nil, "disabling unregisters the service")
        _ = manager.setEnabled(false)
        require(service.unregisterCalls == 1, "an already disabled service is not unregistered twice")

        // Model a permission change made outside the app in System Settings.
        service.status = .requiresApproval
        require(manager.readStatus() == .requiresApproval, "external revocation is read without a cached preference")
        _ = manager.setEnabled(false)
        require(service.unregisterCalls == 2 && manager.readStatus() == .notRegistered,
                "a pending registration can be cancelled")

        service.statusAfterRegister = .requiresApproval
        let pending = manager.setEnabled(true)
        require(pending.status == .requiresApproval && pending.errorMessage == nil,
                "successful registration does not claim enabled while approval is pending")
        _ = manager.setEnabled(false)

        service.statusAfterRegister = .notRegistered
        let unchanged = manager.setEnabled(true)
        require(unchanged.status == .notRegistered, "success does not fabricate an enabled status")

        // The API can throw after the system state has changed. Report both.
        service.statusAfterRegister = .requiresApproval
        service.registrationError = NSError(domain: "LaunchAtLoginChecks", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Registration denied for this check."])
        let failedRegistration = manager.setEnabled(true)
        require(failedRegistration.status == .requiresApproval, "registration failure still rereads the system status")
        require(failedRegistration.errorMessage?.contains("Registration denied") == true,
                "registration errors have a user-facing explanation")

        service.status = .enabled
        service.statusAfterUnregister = .enabled
        service.unregistrationError = NSError(domain: "LaunchAtLoginChecks", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Unregistration denied for this check."])
        let failedUnregistration = manager.setEnabled(false)
        require(failedUnregistration.status == .enabled, "unregistration failure does not claim disabled")
        require(failedUnregistration.errorMessage?.contains("Unregistration denied") == true,
                "unregistration errors have a user-facing explanation")

        service.registrationError = nil
        service.unregistrationError = nil
        service.statusAfterRegister = .enabled
        service.statusAfterUnregister = .notRegistered
        service.status = .notFound
        require(manager.readStatus() == .notFound, "notFound remains visible as the system status")
        require(manager.setEnabled(true).status == .enabled, "registration can be retried after notFound")
        _ = manager.setEnabled(false)

        let registerCallsBeforeToggles = service.registerCalls
        let unregisterCallsBeforeToggles = service.unregisterCalls
        for _ in 0..<5 {
            require(manager.setEnabled(true).status == .enabled, "repeated enable")
            require(manager.setEnabled(false).status == .notRegistered, "repeated disable")
        }
        require(service.registerCalls == registerCallsBeforeToggles + 5, "one registration per enable")
        require(service.unregisterCalls == unregisterCallsBeforeToggles + 5, "one unregistration per disable")
        print("PASS: live status, register/unregister, approval, errors, idempotence, and repeated toggles")
        print("These checks do not change the user's real Login Items.")
    }
}
