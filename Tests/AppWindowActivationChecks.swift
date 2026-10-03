import AppKit

// Exercise real AppKit activation and menu ownership in a temporary agent app.
// No BetterWidgets preferences, widgets, or Login Items are accessed.
@main
struct AppWindowActivationChecks {
    @MainActor static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    @MainActor static func waitUntil(_ condition: () -> Bool, _ message: String) async throws {
        for _ in 0..<150 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        fputs("Activation diagnostics: policy=\(NSApp.activationPolicy().rawValue), registeredPolicy=\(NSRunningApplication.current.activationPolicy.rawValue), active=\(NSApp.isActive), registeredActive=\(NSRunningApplication.current.isActive), ownsMenuBar=\(NSRunningApplication.current.ownsMenuBar), key=\(NSApp.keyWindow?.title ?? "none")\n", stderr)
        require(false, message)
    }

    @MainActor static func makeWindow(_ title: String) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 320, height: 220),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        return window
    }

    @MainActor static func checkAlert(_ presenter: AppWindowPresenter) {
        let alert = NSAlert()
        alert.messageText = "Activation check"
        alert.addButton(withTitle: "OK")
        var ownsMenuDuringAlert = false
        let deadline = Date().addingTimeInterval(3)
        let timer = Timer(timeInterval: 0.02, repeats: true) { _ in
            if alert.window.isKeyWindow && NSRunningApplication.current.ownsMenuBar {
                ownsMenuDuringAlert = true
                NSApp.stopModal(withCode: .alertFirstButtonReturn)
            } else if Date() >= deadline {
                NSApp.abortModal()
            }
        }
        RunLoop.main.add(timer, forMode: .modalPanel)
        defer { timer.invalidate() }
        require(presenter.runModal(alert) == .alertFirstButtonReturn, "alert responds normally")
        require(ownsMenuDuringAlert, "modal alert owns the system menu bar")
    }

    @MainActor static func main() {
        _ = NSApplication.shared
        setbuf(stdout, nil)
        NSApp.setActivationPolicy(.accessory)
        let menu = NSMenu()
        let appItem = NSMenuItem(title: "BetterWidgets Menu Checks", action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: "BetterWidgets Menu Checks")
        appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        NSApp.mainMenu = menu
        DispatchQueue.main.async {
            Task { @MainActor in
                do {
                    try await runChecks()
                    exit(0)
                } catch {
                    fputs("FAIL: \(error)\n", stderr)
                    exit(1)
                }
            }
        }
        // Activation is delivered through AppKit events. A bare async main or
        // finishLaunching() alone does not process those events.
        NSApp.run()
    }

    @MainActor static func runChecks() async throws {
        let presenter = AppWindowPresenter()
        let manager = makeWindow("Manager")
        let about = makeWindow("About")
        let desktopWidget = NSPanel(
            contentRect: NSRect(x: 20, y: 20, width: 40, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        desktopWidget.hidesOnDeactivate = false
        desktopWidget.orderFrontRegardless()
        defer {
            manager.close()
            about.close()
            desktopWidget.close()
        }
        require(NSApp.activationPolicy() == .accessory, "desktop-only launch stays out of the Dock")

        // Start with an already-active accessory app: activating again without
        // changing policy was the original menu ownership regression.
        manager.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        try await waitUntil({ NSApp.isActive }, "agent activates")
        presenter.present(manager)
        try await waitUntil({
            manager.isKeyWindow && NSRunningApplication.current.ownsMenuBar
        }, "opening the manager gives it focus and the system menu bar")
        require(NSApp.activationPolicy() == .regular, "open manager appears in the Dock")
        print("PASS: active agent promotes to a foreground app and owns the menu bar")

        // Hiding exercises a real WindowServer deactivation. Policy must remain
        // regular until foreground windows are closed, also across Spaces.
        NSApp.hide(nil)
        try await waitUntil({ !NSApp.isActive }, "manager deactivates")
        require(NSApp.activationPolicy() == .regular, "leaving the manager keeps its foreground policy")
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        try await waitUntil({
            manager.isKeyWindow && NSRunningApplication.current.ownsMenuBar
        }, "returning to the manager restores menu ownership")
        print("PASS: menu ownership returns after deactivation")

        manager.miniaturize(nil)
        require(NSApp.activationPolicy() == .regular, "minimized manager remains available in the Dock")
        presenter.present(manager)
        try await waitUntil({
            !manager.isMiniaturized && manager.isKeyWindow && NSRunningApplication.current.ownsMenuBar
        }, "reopening a minimized manager restores focus and menu ownership")

        presenter.present(about)
        try await waitUntil({ about.isKeyWindow }, "About gains focus")
        manager.close()
        require(NSApp.activationPolicy() == .regular, "About keeps the app in the Dock after manager closes")
        about.close()
        require(NSApp.activationPolicy() == .accessory, "last foreground window closes return the app to the background")
        require(desktopWidget.isVisible, "returning to the background keeps desktop widgets visible")

        checkAlert(presenter)
        require(NSApp.activationPolicy() == .accessory, "dismissing a standalone alert returns to the background")

        presenter.present(manager)
        manager.close()
        try await Task.sleep(for: .milliseconds(100))
        require(NSApp.activationPolicy() == .accessory, "closing before deferred activation does not reopen the app")
        require(!manager.isVisible, "deferred activation does not resurrect the closed manager")

        presenter.present(manager)
        try await waitUntil({
            manager.isKeyWindow && NSRunningApplication.current.ownsMenuBar
        }, "manager can reopen after returning to the background")
        checkAlert(presenter)
        require(NSApp.activationPolicy() == .regular, "dismissing an alert keeps the open manager in the Dock")
        print("PASS: minimize, About, last-window close, deferred close, and reopen")
    }
}
