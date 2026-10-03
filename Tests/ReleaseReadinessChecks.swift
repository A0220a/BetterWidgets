import AppKit
import Carbon
import Foundation
import ImageIO
import UniformTypeIdentifiers

@main
struct ReleaseReadinessChecks {
    @MainActor static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    @MainActor static func waitUntil(_ condition: () -> Bool, _ message: String) async throws {
        for _ in 0..<150 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        try require(false, message)
    }

    @MainActor static var visibleWidgets: [DesktopWidgetWindow] {
        NSApp.windows.compactMap { $0 as? DesktopWidgetWindow }.filter(\.isVisible)
    }

    @MainActor static func writeImage(_ url: URL, width: Int, height: Int, type: UTType = .png, orientation: Int = 1) throws {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, bitmap.cgImage!, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        try require(CGImageDestinationFinalize(destination), "fixture image is written")
    }

    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.finishLaunching()
        NSApp.setActivationPolicy(.accessory)
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let portraitURL = directory.appendingPathComponent("portrait.png")
        let squareURL = directory.appendingPathComponent("square.png")
        let gifURL = directory.appendingPathComponent("landscape.gif")
        let rotatedURL = directory.appendingPathComponent("rotated.jpg")
        try writeImage(portraitURL, width: 100, height: 200)
        try writeImage(squareURL, width: 120, height: 120)
        try writeImage(gifURL, width: 280, height: 80, type: .gif)
        try writeImage(rotatedURL, width: 100, height: 200, type: .jpeg, orientation: 6)

        let portraitDimensions = await MediaMetadata.dimensions(for: portraitURL, mediaType: .image)
        let gifDimensions = await MediaMetadata.dimensions(for: gifURL, mediaType: .gif)
        let rotatedDimensions = await MediaMetadata.dimensions(for: rotatedURL, mediaType: .image)
        try require(portraitDimensions == CGSize(width: 100, height: 200), "PNG dimensions come from image metadata")
        try require(gifDimensions == CGSize(width: 280, height: 80), "GIF canvas dimensions are preserved")
        try require(rotatedDimensions == CGSize(width: 200, height: 100), "EXIF rotation swaps image dimensions")
        print("PASS: PNG, GIF, and rotated JPEG metadata")

        let store = WidgetStore(fileURL: directory.appendingPathComponent("widgets.json"))
        let manager = WidgetManager(store: store)
        manager.restoreWidgets()
        manager.createWidget(from: portraitURL)
        let id = manager.widgets[0].id
        try await waitUntil({ manager.widgets.first?.size == CGSize(width: 150, height: 300) }, "portrait automatically receives its real size")
        try require(visibleWidgets.count == 1, "portrait is displayed")
        try require(visibleWidgets[0].widgetAspectRatio == 0.5, "resize uses the portrait's real proportions")
        try require(visibleWidgets[0].frame.size == CGSize(width: 150, height: 300), "hosting does not change the media's frame")
        let originalPosition = manager.widgets[0].position
        manager.replaceMedia(for: id, with: squareURL)
        try await waitUntil({ manager.widgets[0].size == CGSize(width: 150, height: 150) }, "replacement fits existing bounds")
        try require(visibleWidgets[0].widgetAspectRatio == 1, "replacement updates resize proportions")
        try require(manager.widgets[0].position == originalPosition, "replacement retains desktop position")
        try require(manager.widgets[0].id == id, "replacement retains identity")
        print("PASS: initial frame, resizing proportions, replacement size, position, and identity")

        try FileManager.default.removeItem(at: squareURL)
        manager.refreshMediaAvailability()
        try require(manager.isMediaUnavailable(for: id), "removed file has an explicit unavailable state")
        try require(visibleWidgets.isEmpty && manager.desktopWidgetCount == 0, "missing media does not leave an invisible desktop window")
        manager.saveWidgets()
        try require(try store.load().widgets.count == 1, "missing widget is retained in saved data")
        try require(manager.widgets[0].isEnabled, "missing file retains the user's enabled preference")
        try writeImage(squareURL, width: 120, height: 120)
        manager.refreshMediaAvailability()
        try require(!manager.isMediaUnavailable(for: id) && visibleWidgets.count == 1, "returned file recovers the enabled widget")

        let renamedURL = directory.appendingPathComponent("renamed.png")
        try FileManager.default.moveItem(at: squareURL, to: renamedURL)
        manager.refreshMediaAvailability()
        try require(manager.widgets[0].imageURL.resolvingSymlinksInPath() == renamedURL.resolvingSymlinksInPath(),
                    "bookmark follows a moved file: \(manager.widgets[0].imageURL.path)")
        try require(!manager.isMediaUnavailable(for: id) && visibleWidgets.count == 1, "moved file remains usable")
        try FileManager.default.removeItem(at: renamedURL)
        manager.refreshMediaAvailability()
        manager.replaceMedia(for: id, with: portraitURL)
        try await waitUntil({ manager.widgets[0].size == CGSize(width: 75, height: 150) }, "missing media can be replaced")
        try require(!manager.isMediaUnavailable(for: id) && visibleWidgets.count == 1, "replacement recovers a missing widget")
        try require(manager.widgets[0].id == id && manager.widgets[0].position == originalPosition, "recovery keeps identity and position")
        print("PASS: deleted, returned, moved, and replaced files without losing saved widgets")
        manager.prepareForTermination()

        // A user interaction while metadata loads must win over automatic sizing.
        let interactionManager = WidgetManager(store: WidgetStore(fileURL: directory.appendingPathComponent("interaction.json")))
        interactionManager.restoreWidgets()
        interactionManager.createWidget(from: portraitURL)
        let editedWindow = visibleWidgets[0]
        let userFrame = NSRect(x: NSScreen.main!.visibleFrame.minX + 40, y: NSScreen.main!.visibleFrame.minY + 40, width: 240, height: 160)
        editedWindow.setFrame(userFrame, display: true)
        try await waitUntil({ editedWindow.widgetAspectRatio == 0.5 }, "metadata updates future resize proportions")
        try require(editedWindow.frame == userFrame, "metadata never resets a user-modified frame")
        interactionManager.prepareForTermination()
        print("PASS: user movement and resizing during metadata loading")

        let restoredManager = WidgetManager(store: WidgetStore(fileURL: directory.appendingPathComponent("interaction.json")))
        restoredManager.restoreWidgets()
        let restoredWindow = visibleWidgets[0]
        try await waitUntil({ restoredWindow.widgetAspectRatio == 0.5 }, "restored widgets use actual media proportions")
        try require(restoredWindow.frame == userFrame, "restoring metadata keeps the saved frame")
        let restoredID = restoredManager.widgets[0].id
        restoredManager.setEnabled(false, for: restoredID)
        restoredManager.setEnabled(true, for: restoredID)
        let reenabledWindow = visibleWidgets[0]
        try await waitUntil({ reenabledWindow.widgetAspectRatio == 0.5 }, "re-enabled widgets use actual media proportions")
        try require(reenabledWindow.frame == userFrame, "re-enabling keeps the saved frame")
        restoredManager.prepareForTermination()
        print("PASS: restored and re-enabled widgets retain their frame and correct resizing proportions")

        let defaultsName = "BetterWidgets.FirstLaunchChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        try require(!AppLaunchPolicy.shouldShowManager(isLoginLaunch: true, defaults: defaults), "login launch stays in the background")
        try require(AppLaunchPolicy.shouldShowManager(isLoginLaunch: false, defaults: defaults), "first manual launch shows the manager")
        let loginEvent = NSAppleEventDescriptor(
            eventClass: kCoreEventClass, eventID: kAEOpenApplication,
            targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID)
        )
        loginEvent.setParam(NSAppleEventDescriptor(enumCode: keyAELaunchedAsLogInItem), forKeyword: keyAEPropData)
        try require(AppLaunchPolicy.isLoginLaunch(loginEvent), "login launch Apple event is recognized")
        try require(!AppLaunchPolicy.isLoginLaunch(nil), "ordinary launch is not classified as login")
        AppLaunchPolicy.recordManagerShown(defaults: defaults)
        try require(!AppLaunchPolicy.shouldShowManager(isLoginLaunch: false, defaults: defaults), "first-launch window is only automatic once")
        try require(!AppLaunchPolicy.shouldShowManager(isLoginLaunch: true, defaults: defaults), "later login launch remains silent")
        print("PASS: first launch, login launch, and persistent first-launch preference")
    }
}
