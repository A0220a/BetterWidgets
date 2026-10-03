import AppKit
import Foundation

// Runs in separate write/read processes against a temporary store, using the
// actual manager and desktop windows. No user widgets are read or changed.
@main
struct WidgetPersistenceChecks {
    @MainActor static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    @MainActor static func settle() async throws {
        try await Task.sleep(for: .milliseconds(500))
    }

    @MainActor static var visibleWidgets: [DesktopWidgetWindow] {
        NSApp.windows.compactMap { $0 as? DesktopWidgetWindow }.filter(\.isVisible)
    }

    @MainActor static func main() async throws {
        _ = NSApplication.shared
        setbuf(stdout, nil)
        NSApp.finishLaunching()
        NSApp.setActivationPolicy(.accessory)
        let directory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let fileURL = directory.appendingPathComponent("widgets.json")
        let store = WidgetStore(fileURL: fileURL)
        let manager = WidgetManager(store: store)

        switch CommandLine.arguments[1] {
        case "write":
            manager.restoreWidgets()
            let mediaURL = directory.appendingPathComponent("widget.png")
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 100,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            )!
            try bitmap.representation(using: .png, properties: [:])!.write(to: mediaURL)
            manager.setEditMode(true)
            manager.createWidget(from: mediaURL)
            try require(manager.widgets.count == 1, "creation publishes a widget")
            let enabledID = manager.widgets[0].id
            try require(!visibleWidgets.isEmpty, "creation displays a desktop window")
            let window = visibleWidgets[0]
            try require(NSScreen.main != nil, "checks require a macOS desktop session")
            let screen = NSScreen.main!.visibleFrame
            let frame = NSRect(x: screen.minX + 60, y: screen.minY + 80, width: 240, height: 160)
            // Move immediately, before the metadata task runs. Its result must
            // not reset the user's position or size.
            window.setFrame(frame, display: true)
            try await settle()
            let saved = try store.load().widgets.first { $0.id == enabledID }!
            try require(saved.position == frame.origin, "move is saved without explicitly quitting")
            try require(saved.size == frame.size, "resize survives delayed metadata")
            try require(saved.mediaBookmarkData != nil, "media access bookmark is saved")

            manager.createWidget(from: mediaURL)
            let disabledID = manager.widgets.first { $0.id != enabledID }!.id
            manager.setEnabled(false, for: disabledID)
            try await settle()
            manager.prepareForTermination()
            let snapshot = try store.load()
            try require(snapshot.widgets.count == 2, "shutdown must retain all widgets")
            try require(snapshot.widgets.filter(\.isEnabled).count == 1, "enabled state is saved")
            try require(visibleWidgets.isEmpty, "shutdown closes desktop windows")
            print("PASS: creation, frame autosave, enabled state, bookmarks, and shutdown")

        case "read":
            let beforeRestore = try Data(contentsOf: fileURL)
            let saved = try store.load().widgets
            manager.restoreWidgets()
            try require(manager.widgets.count == 2, "both widgets return to the main-window list")
            try require(Set(manager.widgets.map(\.id)) == Set(saved.map(\.id)), "widget identities survive restart")
            try require(visibleWidgets.count == 1, "only enabled widgets appear automatically")
            let enabled = saved.first(where: \.isEnabled)!
            try require(visibleWidgets[0].frame.origin == enabled.position, "desktop position survives restart")
            try require(visibleWidgets[0].frame.size == enabled.size, "desktop size survives restart")
            try require(!manager.isEditMode, "widgets restore in desktop mode")
            try require(try Data(contentsOf: fileURL) == beforeRestore, "restoring does not overwrite the saved file")
            manager.restoreWidgets()
            try require(visibleWidgets.count == 1, "repeated restoration does not duplicate windows")

            let disabled = saved.first { !$0.isEnabled }!
            manager.setEnabled(true, for: disabled.id)
            try require(visibleWidgets.count == 2, "a restored disabled widget can be enabled")
            manager.deleteWidget(withID: disabled.id)
            try require(try store.load().widgets.count == 1, "explicit deletion is saved")
            manager.prepareForTermination()
            print("PASS: fresh-process restoration, position, size, disabled widgets, and deletion")

        case "compatibility":
            let model = WidgetModel(imageURL: directory.appendingPathComponent("legacy.png"))
            let data = try JSONEncoder().encode([model])
            try data.write(to: fileURL)
            try require(try store.load().widgets[0].id == model.id, "legacy array saves remain readable")
            var dictionary = (try JSONSerialization.jsonObject(with: data) as! [[String: Any]])[0]
            dictionary.removeValue(forKey: "mediaType")
            dictionary.removeValue(forKey: "isEnabled")
            dictionary.removeValue(forKey: "isMuted")
            try JSONSerialization.data(withJSONObject: ["widgets": [dictionary]]).write(to: fileURL)
            let restored = try store.load()
            try require(restored.folders.isEmpty, "older snapshots can omit folders")
            try require(restored.widgets[0].mediaType == .image && restored.widgets[0].isEnabled,
                    "older widgets receive compatible defaults")

            let portrait = WidgetModel(
                imageURL: directory.appendingPathComponent("widget.png"),
                position: NSScreen.main!.visibleFrame.origin,
                size: CGSize(width: 60, height: 300)
            )
            try store.save(widgets: [portrait], folders: [])
            let portraitManager = WidgetManager(store: store)
            portraitManager.restoreWidgets()
            try require(visibleWidgets[0].frame.size == portrait.size, "small portrait widgets retain their aspect ratio")
            portraitManager.prepareForTermination()

            let corruptData = Data("{incomplete save".utf8)
            try corruptData.write(to: fileURL)
            manager.restoreWidgets()
            try require(manager.persistenceError != nil, "load failures are visible")
            manager.saveWidgets()
            manager.prepareForTermination()
            try require(try Data(contentsOf: fileURL) == corruptData, "a failed load cannot erase saved data")

            let unwritableStore = WidgetStore(fileURL: directory)
            let failedSaveManager = WidgetManager(store: unwritableStore)
            failedSaveManager.saveWidgets()
            try require(failedSaveManager.persistenceError != nil, "save failures are visible")
            print("PASS: older saves, load failure protection, and save error reporting")

        default:
            fatalError("Unknown check")
        }
    }
}
