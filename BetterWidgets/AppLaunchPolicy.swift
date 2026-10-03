import Carbon
import Foundation

enum AppLaunchPolicy {
    private static let openedManagerKey = "hasOpenedWidgetManager"

    static func isLoginLaunch(_ event: NSAppleEventDescriptor?) -> Bool {
        event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    static func shouldShowManager(isLoginLaunch: Bool, defaults: UserDefaults = .standard) -> Bool {
        !isLoginLaunch && !defaults.bool(forKey: openedManagerKey)
    }

    static func recordManagerShown(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: openedManagerKey)
    }
}
