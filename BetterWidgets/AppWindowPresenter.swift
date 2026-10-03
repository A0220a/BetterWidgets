import AppKit

/// Foreground windows need a regular application to own the system menu bar.
/// Keep that policy while they are open, including when another Space is active.
@MainActor
final class AppWindowPresenter: NSObject, NSWindowDelegate {
    private let windows = NSHashTable<NSWindow>.weakObjects()
    private var modalCount = 0
    private var activationRequest = 0

    func present(_ window: NSWindow) {
        windows.add(window)
        window.delegate = self
        promoteToForeground()

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Let status-menu tracking end before requesting focus again.
        activationRequest += 1
        let request = activationRequest
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window,
                  self.activationRequest == request,
                  self.windows.contains(window),
                  window.isVisible, !window.isMiniaturized else { return }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func runModal(_ alert: NSAlert) -> NSApplication.ModalResponse {
        modalCount += 1
        promoteToForeground()
        NSApp.activate(ignoringOtherApps: true)
        defer {
            modalCount -= 1
            restoreBackgroundPolicyIfNeeded()
        }
        return alert.runModal()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        windows.remove(window)
        restoreBackgroundPolicyIfNeeded()
    }

    private func promoteToForeground() {
        guard NSApp.activationPolicy() != .regular else { return }
        // An already-active agent still belongs to the previous app's menu
        // session. Hiding yields that session through WindowServer; merely
        // calling deactivate() would only change AppKit's local active state.
        if NSApp.isActive {
            NSApp.hide(nil)
            NSApp.unhideWithoutActivation()
        }
        NSApp.setActivationPolicy(.regular)
    }

    private func restoreBackgroundPolicyIfNeeded() {
        guard windows.allObjects.isEmpty, modalCount == 0 else { return }
        activationRequest += 1
        NSApp.setActivationPolicy(.accessory)
    }
}
