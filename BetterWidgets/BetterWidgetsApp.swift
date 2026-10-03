//
//  BetterWidgetsApp.swift
//  BetterWidgets
//
//  Created by madi on 02.09.2026.
//

import SwiftUI
import AppKit
import ServiceManagement

@main
struct BetterWidgetsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The manager window is owned by AppDelegate so it can be reopened
        // reliably from the status item and application reopen callback.
        Settings { EmptyView() }
            .commands {
                // There is no separate settings UI; avoid an empty Settings window.
                CommandGroup(replacing: .appSettings) {}
                CommandGroup(replacing: .appInfo) {
                    Button("About BetterWidgets") { appDelegate.showAboutWindow() }
                }
            }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let widgetManager = WidgetManager()

    private let launchAtLoginManager = LaunchAtLoginManager()
    private let windowPresenter = AppWindowPresenter()
    private var statusItem: NSStatusItem?
    private var managerWindowController: NSWindowController?
    private var aboutWindowController: NSWindowController?
    private var mediaRefreshTimer: Timer?
    private var launchAtLoginItem: NSMenuItem?
    private var launchAtLoginStatusItem: NSMenuItem?

    private let statusIconName = "rectangle.grid.2x2"

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start in the background. The presenter enables the Dock and app menu
        // only while a foreground window is open; LSUIElement avoids a launch flash.
        NSApp.setActivationPolicy(.accessory)
        widgetManager.restoreWidgets()
        installStatusItemIfNeeded()
        mediaRefreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.managerWindowController?.window?.isVisible == true else { return }
                self.widgetManager.refreshMediaAvailability()
            }
        }
        if AppLaunchPolicy.shouldShowManager(
            isLoginLaunch: AppLaunchPolicy.isLoginLaunch(NSAppleEventManager.shared().currentAppleEvent)
        ) {
            showWidgetManager()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        mediaRefreshTimer?.invalidate()
        widgetManager.prepareForTermination()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        widgetManager.refreshMediaAvailability()
    }

    @objc private func showAbout(_ sender: Any?) {
        showAboutWindow()
    }

    func showAboutWindow() {
        if aboutWindowController == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: AboutView()))
            window.title = "About BetterWidgets"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            aboutWindowController = NSWindowController(window: window)
        }
        if let window = aboutWindowController?.window {
            windowPresenter.present(window)
        }
    }

    @objc private func openWidgetManager(_ sender: Any?) {
        showWidgetManager()
    }

    @objc private func editWidgets(_ sender: Any?) {
        widgetManager.setEditMode(true)
        showWidgetManager()
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(sender)
    }

    @objc private func toggleLaunchAtLogin(_ sender: Any?) {
        let status = launchAtLoginManager.readStatus()
        let shouldEnable: Bool
        switch status {
        case .enabled, .requiresApproval:
            // A pending registration can be cancelled with the same control.
            shouldEnable = false
        case .notRegistered, .notFound:
            shouldEnable = true
        @unknown default:
            return
        }

        let result = launchAtLoginManager.setEnabled(shouldEnable)
        updateLaunchAtLoginMenu(status: result.status)
        if let errorMessage = result.errorMessage {
            showLaunchAtLoginMessage(errorMessage)
        } else if shouldEnable && result.status == .requiresApproval {
            showLaunchAtLoginMessage(
                "Allow BetterWidgets in System Settings → General → Login Items.",
                offersSystemSettings: true
            )
        } else if (shouldEnable && result.status != .enabled) || (!shouldEnable && result.status != .notRegistered) {
            showLaunchAtLoginMessage(
                "macOS has not confirmed the change. Check System Settings → General → Login Items and try again.",
                offersSystemSettings: true
            )
        }
    }

    @objc private func openLoginItemsSettings(_ sender: Any?) {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func showLaunchAtLoginMessage(_ message: String, offersSystemSettings: Bool = false) {
        let alert = NSAlert()
        alert.messageText = "Launch at Login"
        alert.informativeText = message
        alert.alertStyle = .informational
        if offersSystemSettings {
            alert.addButton(withTitle: "Open System Settings")
        }
        alert.addButton(withTitle: "OK")
        if windowPresenter.runModal(alert) == .alertFirstButtonReturn && offersSystemSettings {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateLaunchAtLoginMenu()
    }

    private func updateLaunchAtLoginMenu(status: SMAppService.Status? = nil) {
        guard let launchAtLoginItem, let launchAtLoginStatusItem else { return }
        let currentStatus = status ?? launchAtLoginManager.readStatus()
        launchAtLoginItem.isEnabled = true
        launchAtLoginStatusItem.isHidden = true
        launchAtLoginStatusItem.isEnabled = false

        switch currentStatus {
        case .enabled:
            launchAtLoginItem.state = .on
            launchAtLoginItem.toolTip = "BetterWidgets will launch automatically when you log in."
        case .notRegistered:
            launchAtLoginItem.state = .off
            launchAtLoginItem.toolTip = "Launch BetterWidgets automatically when you log in."
        case .requiresApproval:
            launchAtLoginItem.state = .mixed
            launchAtLoginItem.toolTip = "Approval is required in System Settings → General → Login Items. Click again to cancel registration."
            launchAtLoginStatusItem.title = "Approval Required — Open System Settings…"
            launchAtLoginStatusItem.isHidden = false
            launchAtLoginStatusItem.isEnabled = true
        case .notFound:
            launchAtLoginItem.state = .off
            launchAtLoginItem.toolTip = "macOS could not locate this app. Open an installed, signed copy of BetterWidgets and try again."
            launchAtLoginStatusItem.title = "Launch at Login Unavailable"
            launchAtLoginStatusItem.isHidden = false
        @unknown default:
            launchAtLoginItem.state = .off
            launchAtLoginItem.isEnabled = false
            launchAtLoginItem.toolTip = "macOS returned an unknown Login Items status."
            launchAtLoginStatusItem.title = "Launch at Login Status Unknown"
            launchAtLoginStatusItem.isHidden = false
        }
    }

    @objc private func hideMenuBarIcon(_ sender: Any?) {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    private func installStatusItemIfNeeded() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(
                systemSymbolName: statusIconName,
                accessibilityDescription: "BetterWidgets"
            )
            image?.isTemplate = true
            button.image = image
            button.toolTip = "BetterWidgets"
        }

        let menu = NSMenu()
        menu.delegate = self
        // Keep unavailable/unknown states disabled instead of letting AppKit
        // automatically enable every item that has an action.
        menu.autoenablesItems = false
        menu.addItem(NSMenuItem(
            title: "Open Widget Manager",
            action: #selector(openWidgetManager(_:)),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(
            title: "Edit Widgets",
            action: #selector(editWidgets(_:)),
            keyEquivalent: ""
        ))
        menu.addItem(.separator())

        let loginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin(_:)),
            keyEquivalent: ""
        )
        launchAtLoginItem = loginItem
        menu.addItem(loginItem)
        let loginStatusItem = NSMenuItem(
            title: "",
            action: #selector(openLoginItemsSettings(_:)),
            keyEquivalent: ""
        )
        launchAtLoginStatusItem = loginStatusItem
        menu.addItem(loginStatusItem)
        updateLaunchAtLoginMenu()
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(
            title: "About BetterWidgets",
            action: #selector(showAbout(_:)),
            keyEquivalent: ""
        ))
        menu.addItem(.separator())

        let hideItem = NSMenuItem(
            title: "Hide Menu Bar Icon",
            action: #selector(hideMenuBarIcon(_:)),
            keyEquivalent: ""
        )
        hideItem.toolTip = "Open BetterWidgets again from Finder or Launchpad to restore the icon. Widgets will keep running."
        menu.addItem(hideItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quit(_:)),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = [.command]
        menu.addItem(quitItem)

        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        print("[Lifecycle] reopen")
        installStatusItemIfNeeded()
        showWidgetManager()
        // The manager is restored explicitly, including when desktop widget
        // windows make hasVisibleWindows true. No default handling is needed.
        return false
    }

    private func createManagerWindowIfNeeded() {
        guard managerWindowController == nil else { return }

        let hostingController = NSHostingController(
            rootView: ContentView(widgetManager: widgetManager, onShowAbout: { [weak self] in self?.showAboutWindow() })
        )
        hostingController.sizingOptions = []
        let window = NSWindow(contentViewController: hostingController)
        window.title = "BetterWidgets"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 640, height: 480)
        window.setContentSize(NSSize(width: 900, height: 680))
        window.center()

        managerWindowController = NSWindowController(window: window)
    }

    private func showWidgetManager() {
        createManagerWindowIfNeeded()

        guard let window = managerWindowController?.window else { return }

        widgetManager.refreshMediaAvailability()
        print("[Lifecycle] show manager")
        windowPresenter.present(window)
        AppLaunchPolicy.recordManagerShown()
    }
}
