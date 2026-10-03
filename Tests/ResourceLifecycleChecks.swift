import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

@main
struct ResourceLifecycleChecks {
    @MainActor static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    @MainActor static func waitUntil(_ condition: () -> Bool, _ message: String) async throws {
        for _ in 0..<250 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        try require(false, message)
    }

    @MainActor static func image(_ color: NSColor) -> CGImage {
        let context = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8,
                                bytesPerRow: 128, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(color.usingColorSpace(.deviceRGB)!.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        return context.makeImage()!
    }

    @MainActor static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    @MainActor static func writeMedia(_ directory: URL) throws -> (URL, URL) {
        let png = directory.appendingPathComponent("still.png")
        let pngDestination = CGImageDestinationCreateWithURL(png as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(pngDestination, image(.red), nil)
        try require(CGImageDestinationFinalize(pngDestination), "PNG fixture is written")
        let gif = directory.appendingPathComponent("animated.gif")
        let gifDestination = CGImageDestinationCreateWithURL(gif as CFURL, UTType.gif.identifier as CFString, 2, nil)!
        for color in [NSColor.red, .blue] {
            CGImageDestinationAddImage(gifDestination, image(color), [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.02]
            ] as CFDictionary)
        }
        try require(CGImageDestinationFinalize(gifDestination), "GIF fixture is written")
        return (png, gif)
    }

    @MainActor static func checkSandboxAccess(_ directory: URL, png: URL) async throws {
        var starts: [URL] = []
        var stops: [URL] = []
        var allowStart = false
        var pool: SecurityScopedAccessPool? = SecurityScopedAccessPool(
            start: { starts.append($0); return allowStart }, stop: { stops.append($0) }
        )
        let firstOwner = pool!.acquire(png)
        allowStart = true
        let secondOwner = pool!.acquire(png)
        pool!.release(firstOwner)
        try require(stops.isEmpty, "a shared sandbox extension remains until its final owner releases it")
        pool!.release(secondOwner)
        try require(starts.count == 2 && stops == [png], "a later valid scope is acquired and balanced exactly once")
        _ = pool!.acquire(png)
        pool = nil
        try require(stops.count == 2, "deallocation releases outstanding sandbox extensions")

        starts.removeAll()
        stops.removeAll()
        let access = SecurityScopedAccessPool(start: { starts.append($0); return true }, stop: { stops.append($0) })
        let manager = WidgetManager(store: WidgetStore(fileURL: directory.appendingPathComponent("folders.json")), securityScopedAccess: access)
        manager.restoreWidgets()
        let original = directory.appendingPathComponent("original", isDirectory: true)
        let moved = directory.appendingPathComponent("moved", isDirectory: true)
        let movedAgain = directory.appendingPathComponent("moved-again", isDirectory: true)
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: png, to: original.appendingPathComponent("file.png"))
        try FileManager.default.createDirectory(at: original.appendingPathComponent("directory.mp4"), withIntermediateDirectories: true)
        try manager.addFolder(at: original)
        let folder = manager.folders[0]
        try await waitUntil({ manager.mediaItems[folder.id]?.count == 1 }, "folder scans exclude directories with media extensions")
        manager.toggleMediaItem(manager.mediaItems[folder.id]![0])
        let widgetID = manager.widgets[0].id
        manager.setEnabled(false, for: widgetID)
        try FileManager.default.moveItem(at: original, to: moved)
        manager.refreshFolder(folder)
        manager.refreshMediaAvailability()
        try await waitUntil({ manager.mediaItems[folder.id]?.first?.url.deletingLastPathComponent().resolvingSymlinksInPath() == moved.resolvingSymlinksInPath() }, "folder bookmark follows its move")
        try require(stops.contains { $0.standardizedFileURL == original.standardizedFileURL }, "refresh releases the previous folder scope")
        try require(manager.folders[0].lastKnownURL?.resolvingSymlinksInPath() == moved.resolvingSymlinksInPath(), "moved folder location is persisted")
        try FileManager.default.moveItem(at: moved, to: movedAgain)
        manager.removeFolder(withID: folder.id)
        try require(stops.contains { $0 == starts.first { $0.lastPathComponent == "moved" } }, "removing a moved folder releases the acquired URL")
        manager.deleteWidget(withID: widgetID)
        let countBeforeRefresh = starts.count
        manager.refreshFolder(folder)
        try await Task.sleep(for: .milliseconds(100))
        try require(starts.count == countBeforeRefresh && manager.mediaItems[folder.id] == nil, "stale scans and refreshes cannot resurrect removed folders or permissions")
        manager.prepareForTermination()
        try require(starts.count == stops.count, "all folder scopes are balanced after shutdown")
        print("PASS: sandbox scopes, moved folders, asynchronous scans, and removed-folder races")
    }

    @MainActor static func writeVideo(_ directory: URL) async throws -> URL {
        let url = directory.appendingPathComponent("playable.mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 32, AVVideoHeightKey: 32
        ])
        let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 32, kCVPixelBufferHeightKey as String: 32
        ])
        writer.add(input)
        try require(writer.startWriting(), "video writer starts")
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<3 {
            try await waitUntil({ input.isReadyForMoreMediaData }, "video writer accepts a frame")
            var buffer: CVPixelBuffer?
            try require(CVPixelBufferCreate(kCFAllocatorDefault, 32, 32, kCVPixelFormatType_32BGRA, nil, &buffer) == kCVReturnSuccess, "video buffer is created")
            CVPixelBufferLockBaseAddress(buffer!, [])
            memset(CVPixelBufferGetBaseAddress(buffer!), 255, CVPixelBufferGetBytesPerRow(buffer!) * 32)
            CVPixelBufferUnlockBaseAddress(buffer!, [])
            try require(adapter.append(buffer!, withPresentationTime: CMTime(value: Int64(frame), timescale: 10)), "video frame is appended")
        }
        writer.endSession(atSourceTime: CMTime(value: 3, timescale: 10))
        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        try require(writer.status == .completed, "video fixture finishes writing")
        return url
    }

    @MainActor static func checkWindows(_ gif: URL) async throws {
        let window = DesktopWidgetWindow(model: WidgetModel(imageURL: gif), isEditMode: false, onReplaceImage: {}, onToggleMute: {}, onDelete: {})
        window.orderFrontRegardless()
        var gifView: NSView?
        try await waitUntil({
            gifView = window.contentView.flatMap { descendants($0).first { String(describing: type(of: $0)) == "GIFPlayerView" } }
            return gifView?.layer?.contents != nil
        }, "GIF starts rendering")
        let firstFrame = gifView?.layer?.contents as AnyObject?
        try await waitUntil({ (gifView?.layer?.contents as AnyObject?) !== firstFrame }, "an attached GIF advances beyond its initial frame")
        let corrupt = gif.deletingLastPathComponent().appendingPathComponent("corrupt.gif")
        try Data("invalid GIF data".utf8).write(to: corrupt)
        window.updateMedia(WidgetModel(imageURL: corrupt))
        try await waitUntil({ gifView?.layer?.contents == nil }, "a corrupt GIF replacement clears the old frame")
        window.updateMedia(WidgetModel(imageURL: gif))
        try await waitUntil({ gifView?.layer?.contents != nil }, "GIF playback resumes after a valid replacement")
        window.closeWithoutNotifyingManager()
        try require(window.contentView == nil, "closed panels release their hosted media even while the window is retained")
        try require(gifView?.layer?.contents == nil, "detached GIF clears decoded frames")
        try await Task.sleep(for: .milliseconds(100))
        try require(gifView?.layer?.contents == nil, "a detached GIF timer cannot resume playback")
        gifView = nil

        let releasedWindows = NSHashTable<DesktopWidgetWindow>.weakObjects()
        for _ in 0..<80 {
            autoreleasepool {
                let panel = DesktopWidgetWindow(model: WidgetModel(imageURL: gif), isEditMode: false, onReplaceImage: {}, onToggleMute: {}, onDelete: {})
                releasedWindows.add(panel)
                panel.orderFrontRegardless()
                panel.closeWithoutNotifyingManager()
            }
        }
        try await waitUntil({ releasedWindows.allObjects.isEmpty }, "all closed widget panels deallocate after repeated creation")
        print("PASS: GIF teardown and 80 create/close cycles without retained widget panels")
    }

    @MainActor static func checkVideo(_ directory: URL) async throws {
        let corrupt = directory.appendingPathComponent("corrupt.mp4")
        try Data("invalid video data".utf8).write(to: corrupt)
        var controller: VideoPlaybackController? = VideoPlaybackController(url: corrupt, isMuted: true)
        weak var releasedController: VideoPlaybackController?
        releasedController = controller
        try await waitUntil({ controller?.playbackErrorMessage != nil }, "corrupt video reports a playback error instead of leaving an empty widget")
        let player = controller!.player
        controller!.stop()
        controller!.stop()
        try require(player.items().isEmpty && player.rate == 0, "stopping disables looping and clears the playback queue")
        controller = nil
        try await waitUntil({ releasedController == nil }, "video observations do not retain their controller")
        let playable = try await writeVideo(directory)
        for _ in 0..<8 {
            controller = VideoPlaybackController(url: playable, isMuted: true)
            releasedController = controller
            try await waitUntil({ controller?.player.currentItem?.status == .readyToPlay }, "valid video becomes playable")
            try require(controller?.playbackErrorMessage == nil, "valid looping video has no error")
            controller!.stop()
            controller = nil
            try await waitUntil({ releasedController == nil }, "playing video controller releases after stop")
        }

        var cache: ThumbnailCache? = ThumbnailCache()
        weak var releasedCache: ThumbnailCache?
        releasedCache = cache
        var previews = 0
        for media in [(playable, WidgetMediaType.video), (directory.appendingPathComponent("animated.gif"), .gif)] {
            cache!.image(for: media.0, mediaType: media.1) { image in
                if image != nil { previews += 1 }
            }
        }
        try await waitUntil({ previews == 2 }, "native video and GIF thumbnail generation succeeds")
        cache = nil
        try await waitUntil({ releasedCache == nil }, "completed native generators do not retain the thumbnail cache")
        print("PASS: corrupt video detection, idempotent stopping, and controller deallocation")
    }

    @MainActor static func checkThumbnails(_ directory: URL, png: URL) async throws {
        var renders = 0
        var callbacks: [(NSImage?) -> Void] = []
        var delivered = 0
        let cache = ThumbnailCache(renderer: { _, _, completion in
            DispatchQueue.main.async { renders += 1; callbacks.append(completion) }
        })
        let preview = NSImage(cgImage: image(.red), size: .zero)
        for _ in 0..<40 {
            cache.image(for: png, mediaType: .image) { _ in delivered += 1 }
        }
        try await waitUntil({ renders == 1 }, "duplicate requests share one thumbnail generation")
        callbacks.removeFirst()(preview)
        try await waitUntil({ delivered == 40 }, "all coalesced requests receive their preview")
        cache.image(for: png, mediaType: .image) { _ in delivered += 1 }
        try await waitUntil({ delivered == 41 }, "cached requests complete")
        try require(renders == 1, "cached previews do not regenerate")

        for name in ["a.png", "b.png", "c.png"] {
            cache.image(for: directory.appendingPathComponent(name), mediaType: .image) { _ in delivered += 1 }
        }
        try await waitUntil({ renders == 3 }, "two distinct requests can start")
        try await Task.sleep(for: .milliseconds(100))
        try require(renders == 3, "asynchronous generation is bounded to two active requests")
        callbacks.removeFirst()(nil)
        try await waitUntil({ renders == 4 }, "a completed request lets the next preview start")
        let remaining = callbacks
        callbacks.removeAll()
        remaining.forEach { $0(preview) }
        try await waitUntil({ delivered == 44 }, "failed and successful previews both finish their requests")

        try Data("new file revision".utf8).write(to: png)
        cache.image(for: png, mediaType: .image) { _ in delivered += 1 }
        try await waitUntil({ renders == 5 }, "changing a file at the same URL invalidates the preview")
        callbacks.removeFirst()(preview)
        try await waitUntil({ delivered == 45 }, "changed-file preview is delivered")
        print("PASS: thumbnail coalescing, cached delivery, concurrency limit, and revision invalidation")
    }

    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.finishLaunching()
        NSApp.setActivationPolicy(.accessory)
        setbuf(stdout, nil)
        if CommandLine.arguments.contains("--baseline") {
            try await Task.sleep(for: .seconds(1))
            print("PASS: empty AppKit baseline")
            return
        }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let (png, gif) = try writeMedia(directory)
        try await checkSandboxAccess(directory, png: png)
        try await checkWindows(gif)
        try await checkVideo(directory)
        try await checkThumbnails(directory, png: png)

        let duplicates = WidgetModel(imageURL: gif)
        let store = WidgetStore(fileURL: directory.appendingPathComponent("duplicate-identities.json"))
        try store.save(widgets: [duplicates, duplicates], folders: [])
        let saved = try Data(contentsOf: directory.appendingPathComponent("duplicate-identities.json"))
        let manager = WidgetManager(store: store)
        manager.restoreWidgets()
        try require(manager.persistenceError != nil && manager.widgets.isEmpty, "duplicate saved identities are rejected before creating windows")
        manager.prepareForTermination()
        try require(try Data(contentsOf: directory.appendingPathComponent("duplicate-identities.json")) == saved, "corrupt duplicate saves are kept unchanged")
        print("PASS: duplicate-identity saves cannot leak windows or erase saved data")
    }
}
