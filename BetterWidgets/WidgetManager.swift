//
//  WidgetManager.swift
//  BetterWidgets
//

import AppKit
import Combine
import UniformTypeIdentifiers

enum WidgetInteractionMode {
    case edit
    case locked
}

@MainActor
final class WidgetManager: ObservableObject {
    private let store: WidgetStore
    private var widgetModels: [UUID: WidgetModel] = [:]
    private var widgetWindows: [UUID: DesktopWidgetWindow] = [:]
    private let securityScopedAccess: SecurityScopedAccessPool
    private var folderAccessURLs: [UUID: URL] = [:]
    private var folderAccessTokens: [UUID: UUID] = [:]
    private var widgetAccessTokens: [UUID: UUID] = [:]
    private var folderScans: [UUID: BlockOperation] = [:]
    private let folderScanQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "BetterWidgets.folder-scan"
        queue.maxConcurrentOperationCount = 2
        queue.qualityOfService = .userInitiated
        return queue
    }()
    private var pendingSave: Task<Void, Never>?
    private var hasRestoredWidgets = false
    private var canSaveWidgets = true
    private var isTerminating = false
    @Published private(set) var widgets: [WidgetModel] = []
    @Published private(set) var folders: [MediaFolder] = []
    @Published private(set) var mediaItems: [UUID: [MediaItem]] = [:]
    @Published private(set) var interactionMode: WidgetInteractionMode = .locked
    @Published private(set) var selectedWidgetID: UUID?
    @Published private(set) var isMediaDropTarget = false
    @Published private(set) var persistenceError: String?
    @Published private(set) var unavailableWidgetIDs: Set<UUID> = []

    init(store: WidgetStore? = nil, securityScopedAccess: SecurityScopedAccessPool? = nil) {
        self.store = store ?? WidgetStore()
        self.securityScopedAccess = securityScopedAccess ?? SecurityScopedAccessPool()
    }

    var isEditMode: Bool {
        interactionMode == .edit
    }

    var desktopWidgetCount: Int {
        widgets.filter { $0.isEnabled && !unavailableWidgetIDs.contains($0.id) }.count
    }

    func isMediaUnavailable(for widgetID: UUID) -> Bool {
        unavailableWidgetIDs.contains(widgetID)
    }

    /// Keep unavailable widgets saved and follow moved files through bookmarks.
    func refreshMediaAvailability() {
        guard !isTerminating else { return }
        var unavailable: Set<UUID> = []
        var updatedMediaAccess = false
        for (id, savedModel) in widgetModels {
            var model = savedModel
            if !mediaIsAvailable(at: model.imageURL), let bookmark = model.mediaBookmarkData {
                var stale = false
                if let resolved = try? URL(
                    resolvingBookmarkData: bookmark, options: [.withSecurityScope],
                    relativeTo: nil, bookmarkDataIsStale: &stale
                ), resolved != model.imageURL {
                    acquireWidgetAccess(resolved, widgetID: id)
                    model.imageURL = resolved
                    if stale { model.mediaBookmarkData = MediaLibrarySupport.bookmarkOrLog(for: resolved) }
                    if let key = model.mediaItemKey, let folderID = key.split(separator: ":", maxSplits: 1).first {
                        model.mediaItemKey = "\(folderID):\(resolved.standardizedFileURL.path)"
                    }
                    updatedMediaAccess = true
                }
            }

            if mediaIsAvailable(at: model.imageURL) {
                if unavailableWidgetIDs.contains(id) {
                    model.mediaBookmarkData = MediaLibrarySupport.bookmarkOrLog(for: model.imageURL)
                    updatedMediaAccess = true
                }
                widgetModels[id] = model
                if model.isEnabled, widgetWindows[id] == nil {
                    createWindow(for: model, saveImmediately: false)
                } else if model.imageURL != savedModel.imageURL {
                    widgetWindows[id]?.updateMedia(model)
                }
            } else {
                unavailable.insert(id)
                if let window = widgetWindows.removeValue(forKey: id) {
                    model.position = window.frame.origin
                    model.size = window.frame.size
                    window.closeWithoutNotifyingManager()
                }
                widgetModels[id] = model
            }
        }
        unavailableWidgetIDs = unavailable
        refreshWidgets()
        if updatedMediaAccess { saveWidgets() }
    }

    func addWidget() {
        guard let mediaURL = chooseMedia() else {
            return
        }

        createWidget(from: mediaURL)
    }

    func createWidget(from mediaURL: URL) {
        guard supportsMedia(at: mediaURL) else {
            print("BetterWidgets: unsupported dropped media: \(mediaURL.path)")
            return
        }

        createWidgetImmediately(from: mediaURL, mediaItemKey: nil)
    }

    private func createWidgetImmediately(from mediaURL: URL, mediaItemKey: String?) {
        let mediaType = WidgetMediaType.mediaType(for: mediaURL)
        var model = WidgetModel(
            mediaType: mediaType,
            imageURL: mediaURL,
            position: centeredPosition(for: CGSize(width: 300, height: 200))
        )
        model.mediaItemKey = mediaItemKey
        acquireWidgetAccess(mediaURL, widgetID: model.id)
        model.mediaBookmarkData = MediaLibrarySupport.bookmarkOrLog(for: mediaURL)
        createWidget(model, saveImmediately: true)
        let initialModel = widgetModels[model.id] ?? model

        // Show the new item immediately. Reading media metadata can be slow
        // (especially for animated files or cloud-backed folders), so it must
        // not block publishing the widget list.
        Task { [weak self] in
            let dimensions = await MediaMetadata.dimensions(for: mediaURL, mediaType: mediaType)
            guard let self else { return }
            guard let dimensions else { return }
            self.applyInitialSize(
                MediaMetadata.initialWidgetSize(for: dimensions),
                to: model.id,
                ifUnchangedFrom: initialModel
            )
        }
    }

    func restoreWidgets() {
        guard !hasRestoredWidgets else { return }
        let snapshot: WidgetStore.Snapshot
        do {
            snapshot = try store.load()
        } catch {
            // A failed read must never turn into an empty save at shutdown.
            canSaveWidgets = false
            persistenceError = "Unable to restore saved widgets. The saved file has been kept unchanged. \(error.localizedDescription)"
            print("[Persistence] Load failed: \(error.localizedDescription)")
            return
        }
        canSaveWidgets = true
        persistenceError = nil
        folders = snapshot.folders
        folders.forEach { refreshFolder($0) }
        var restoredCount = 0
        for savedModel in snapshot.widgets {
            var restoredModel = savedModel
            resolveMediaAccess(for: &restoredModel)
            if !FileManager.default.fileExists(atPath: restoredModel.imageURL.path) {
                print("[Widget Restore] Media unavailable: \(savedModel.imageURL.path)")
            }
            widgetModels[restoredModel.id] = validatedModel(from: restoredModel)
            if restoredModel.isEnabled {
                createWindow(for: widgetModels[restoredModel.id]!, saveImmediately: false)
            }
            restoredCount += 1
        }

        refreshWidgets()
        refreshMediaAvailability()
        hasRestoredWidgets = true
        print("[Widget Restore] Restored \(restoredCount) widgets, \(widgetWindows.count) enabled windows")
    }

    func saveWidgets() {
        pendingSave?.cancel()
        pendingSave = nil
        guard canSaveWidgets, !isTerminating else { return }
        // Capture the actual windows as well as delegate updates, including a
        // last move or resize immediately before quitting.
        for (id, window) in widgetWindows {
            widgetModels[id]?.position = window.frame.origin
            widgetModels[id]?.size = window.frame.size
        }
        do {
            try store.save(
                widgets: widgetModels.values.sorted { $0.id.uuidString < $1.id.uuidString },
                folders: folders
            )
            persistenceError = nil
        } catch {
            persistenceError = "Unable to save widgets. \(error.localizedDescription)"
            print("[Persistence] Save failed: \(error.localizedDescription)")
        }
    }

    func prepareForTermination() {
        saveWidgets()
        isTerminating = true
        // Closing windows during shutdown is not a user deleting widgets.
        widgetWindows.values.forEach { $0.closeWithoutNotifyingManager() }
        widgetWindows.removeAll()
        folderScanQueue.cancelAllOperations()
        folderScans.removeAll()
        securityScopedAccess.releaseAll()
        folderAccessURLs.removeAll()
        folderAccessTokens.removeAll()
        widgetAccessTokens.removeAll()
    }

    private func scheduleSave() {
        guard hasRestoredWidgets, !isTerminating else { return }
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(200)) }
            catch { return }
            self?.saveWidgets()
        }
    }

    func setEditMode(_ isEnabled: Bool) {
        interactionMode = isEnabled ? .edit : .locked
        widgetWindows.values.forEach { $0.setEditMode(isEnabled) }
    }

    func selectWidget(withID widgetID: UUID, activateEditing: Bool = false) {
        selectedWidgetID = widgetID
        if activateEditing {
            setEditMode(true)
            widgetWindows[widgetID]?.orderFront(nil)
        }
        widgetWindows.forEach { id, window in
            window.setSelected(id == widgetID)
        }
    }

    func setMediaDropTarget(_ isTargeted: Bool) {
        isMediaDropTarget = isTargeted
    }

    func replaceWidget(withID widgetID: UUID) {
        replaceImage(for: widgetID)
    }

    func deleteWidget(withID widgetID: UUID) {
        deleteWidgetInternally(withID: widgetID)
    }

    func toggleMute(for widgetID: UUID) {
        toggleMuteInternally(for: widgetID)
    }

    func setEnabled(_ enabled: Bool, for widgetID: UUID) {
        guard var model = widgetModels[widgetID], model.isEnabled != enabled else { return }
        model.isEnabled = enabled
        widgetModels[widgetID] = model
        if enabled {
            createWindow(for: model, saveImmediately: false)
        } else {
            widgetWindows[widgetID]?.closeWithoutNotifyingManager()
            widgetWindows[widgetID] = nil
        }
        refreshWidgets()
        saveWidgets()
    }

    func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try addFolder(at: url)
        } catch {
            print("[Persistence] Folder bookmark save failed: \(error.localizedDescription)")
        }
    }

    func addFolder(at url: URL) throws {
        guard !isTerminating else { return }
        let folder = MediaFolder(
            id: UUID(), displayName: url.lastPathComponent,
            bookmarkData: try MediaLibrarySupport.bookmark(for: url), lastKnownURL: url
        )
        folderAccessTokens[folder.id] = securityScopedAccess.acquire(url)
        folderAccessURLs[folder.id] = url
        folders.append(folder)
        scanFolder(at: url, folderID: folder.id)
        saveWidgets()
    }

    func refreshFolder(_ folder: MediaFolder) {
        guard !isTerminating,
              let index = folders.firstIndex(where: { $0.id == folder.id }),
              let resolved = MediaLibrarySupport.resolve(folders[index]) else { return }
        if folderAccessURLs[folder.id] != resolved.0 {
            let previousToken = folderAccessTokens.updateValue(securityScopedAccess.acquire(resolved.0), forKey: folder.id)
            if let previousToken { securityScopedAccess.release(previousToken) }
            folderAccessURLs[folder.id] = resolved.0
        }
        let moved = folders[index].lastKnownURL != resolved.0
        folders[index].lastKnownURL = resolved.0
        if resolved.1 || moved {
            if let bookmark = MediaLibrarySupport.bookmarkOrLog(for: resolved.0) {
                folders[index].bookmarkData = bookmark
            }
            if hasRestoredWidgets { saveWidgets() }
        }
        scanFolder(at: resolved.0, folderID: folder.id)
    }

    private func scanFolder(at url: URL, folderID: UUID) {
        folderScans[folderID]?.cancel()
        let operation = BlockOperation()
        operation.addExecutionBlock { [weak self, weak operation] in
            guard let operation, !operation.isCancelled else { return }
            let items = MediaLibrarySupport.scan(url, folderID: folderID)
            guard !operation.isCancelled else { return }
            Task { @MainActor [weak self] in
                guard let self, !self.isTerminating,
                      self.folderScans[folderID] === operation,
                      self.folders.contains(where: { $0.id == folderID }) else { return }
                self.folderScans[folderID] = nil
                self.mediaItems[folderID] = items
            }
        }
        folderScans[folderID] = operation
        folderScanQueue.addOperation(operation)
    }

    func removeFolder(_ folder: MediaFolder) {
        let alert = NSAlert()
        alert.messageText = "Remove this folder from the library?"
        alert.informativeText = "The original folder and its files will not be deleted. Existing widgets will remain in Your Widgets."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        removeFolder(withID: folder.id)
    }

    func removeFolder(withID folderID: UUID) {
        folderScans.removeValue(forKey: folderID)?.cancel()
        folders.removeAll { $0.id == folderID }
        mediaItems[folderID] = nil
        // Release the URL we actually acquired, even if the folder moved again.
        folderAccessURLs[folderID] = nil
        if let token = folderAccessTokens.removeValue(forKey: folderID) { securityScopedAccess.release(token) }
        saveWidgets()
    }

    func toggleMediaItem(_ item: MediaItem) {
        if let widget = widgetModels.values.first(where: { $0.mediaItemKey == item.id }) {
            setEnabled(!widget.isEnabled, for: widget.id)
            return
        }

        createWidgetImmediately(from: item.url, mediaItemKey: item.id)
    }

    private func chooseMedia() -> URL? {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.allowedContentTypes = [.png, .jpeg, .heic, .gif, .mpeg4Movie, .quickTimeMovie]
        openPanel.allowsOtherFileTypes = false

        guard openPanel.runModal() == .OK else { return nil }
        return openPanel.url
    }

    private func createWidget(_ model: WidgetModel, saveImmediately: Bool) {
        let widgetID = model.id
        guard model.isEnabled else {
            widgetModels[widgetID] = model
            refreshWidgets()
            if saveImmediately { saveWidgets() }
            return
        }
        // Newly added media gets its size and ratio from applyInitialSize.
        createWindow(for: model, saveImmediately: saveImmediately, readMediaAspectRatio: false)
    }

    private func createWindow(for model: WidgetModel, saveImmediately: Bool, readMediaAspectRatio: Bool = true) {
        let widgetID = model.id
        guard mediaIsAvailable(at: model.imageURL) else {
            widgetModels[widgetID] = model
            unavailableWidgetIDs.insert(widgetID)
            refreshWidgets()
            if saveImmediately { saveWidgets() }
            return
        }
        unavailableWidgetIDs.remove(widgetID)
        let window = DesktopWidgetWindow(
            model: model,
            isEditMode: isEditMode,
            onReplaceImage: { [weak self] in self?.replaceImage(for: widgetID) },
            onToggleMute: { [weak self] in self?.toggleMute(for: widgetID) },
            onDelete: { [weak self] in self?.deleteWidget(withID: widgetID) }
        )

        window.onClose = { [weak self] in
            self?.removeWidget(withID: widgetID)
        }
        window.onFrameChange = { [weak self] frame in
            self?.updateWidget(withID: widgetID, frame: frame)
        }
        window.onInteractionEnded = { [weak self] in
            self?.saveWidgets()
        }

        var displayedModel = model
        displayedModel.position = window.frame.origin
        displayedModel.size = window.frame.size
        widgetModels[widgetID] = displayedModel
        widgetWindows[widgetID] = window
        refreshWidgets()
        window.makeKeyAndOrderFront(nil)

        if readMediaAspectRatio {
            // Restored and re-enabled widgets retain their saved frame, while
            // subsequent resizing follows the media's real proportions.
            Task { [weak self, weak window] in
                guard let dimensions = await MediaMetadata.dimensions(for: model.imageURL, mediaType: model.mediaType),
                      let self, !self.isTerminating, let window,
                      self.widgetWindows[widgetID] === window,
                      self.widgetModels[widgetID]?.imageURL == model.imageURL else { return }
                window.updateResizeAspectRatio(for: MediaMetadata.initialWidgetSize(for: dimensions))
            }
        }

        if saveImmediately {
            saveWidgets()
        }
    }

    private func replaceImage(for widgetID: UUID) {
        guard let imageURL = chooseMedia() else { return }
        replaceMedia(for: widgetID, with: imageURL)
    }

    func replaceMedia(for widgetID: UUID, with imageURL: URL) {
        guard supportsMedia(at: imageURL), var model = widgetModels[widgetID] else { return }

        model.imageURL = imageURL
        model.mediaType = WidgetMediaType.mediaType(for: imageURL)
        acquireWidgetAccess(imageURL, widgetID: widgetID)
        model.mediaBookmarkData = MediaLibrarySupport.bookmarkOrLog(for: imageURL)
        model.mediaItemKey = nil
        widgetModels[widgetID] = model
        refreshWidgets()
        widgetWindows[widgetID]?.updateMedia(model)
        refreshMediaAvailability()
        saveWidgets()

        let initialModel = widgetModels[widgetID] ?? model
        Task { [weak self] in
            guard let dimensions = await MediaMetadata.dimensions(for: imageURL, mediaType: model.mediaType),
                  dimensions.width > 0, dimensions.height > 0 else { return }
            let scale = min(initialModel.size.width / dimensions.width, initialModel.size.height / dimensions.height)
            self?.applyInitialSize(
                CGSize(width: dimensions.width * scale, height: dimensions.height * scale),
                to: widgetID, ifUnchangedFrom: initialModel, recenter: false
            )
        }
    }

    private func deleteWidgetInternally(withID widgetID: UUID) {
        if let window = widgetWindows[widgetID] {
            window.close()
        } else {
            widgetModels[widgetID] = nil
            unavailableWidgetIDs.remove(widgetID)
            if selectedWidgetID == widgetID { selectedWidgetID = nil }
            releaseWidgetAccess(widgetID)
            refreshWidgets()
            saveWidgets()
        }
    }

    private func toggleMuteInternally(for widgetID: UUID) {
        guard var model = widgetModels[widgetID], model.mediaType == .video else { return }

        model.isMuted.toggle()
        widgetModels[widgetID] = model
        refreshWidgets()
        widgetWindows[widgetID]?.updateMute(model.isMuted)
        saveWidgets()
    }

    private func updateWidget(withID widgetID: UUID, frame: NSRect) {
        guard var model = widgetModels[widgetID] else { return }

        model.position = frame.origin
        model.size = frame.size
        widgetModels[widgetID] = model
        refreshWidgets()
        scheduleSave()
    }

    private func applyInitialSize(_ size: CGSize, to widgetID: UUID, ifUnchangedFrom initialModel: WidgetModel, recenter: Bool = true) {
        guard !isTerminating,
              var model = widgetModels[widgetID],
              model.imageURL == initialModel.imageURL else { return }
        widgetWindows[widgetID]?.updateResizeAspectRatio(for: size)
        // Metadata may arrive after a user has moved or resized the widget.
        guard model.position == initialModel.position,
              model.size == initialModel.size else { return }

        model.size = size
        if recenter { model.position = centeredPosition(for: size) }
        widgetModels[widgetID] = model
        if let window = widgetWindows[widgetID] {
            window.setFrame(NSRect(origin: model.position, size: size), display: true)
        }
        refreshWidgets()
        saveWidgets()
    }

    private func removeWidget(withID widgetID: UUID) {
        guard !isTerminating else { return }
        widgetWindows[widgetID] = nil
        widgetModels[widgetID] = nil
        unavailableWidgetIDs.remove(widgetID)
        releaseWidgetAccess(widgetID)
        if selectedWidgetID == widgetID {
            selectedWidgetID = nil
        }
        refreshWidgets()
        saveWidgets()
    }

    private func refreshWidgets() {
        widgets = widgetModels.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private func acquireWidgetAccess(_ url: URL, widgetID: UUID) {
        let previousToken = widgetAccessTokens.updateValue(securityScopedAccess.acquire(url), forKey: widgetID)
        if let previousToken { securityScopedAccess.release(previousToken) }
    }

    private func releaseWidgetAccess(_ widgetID: UUID) {
        if let token = widgetAccessTokens.removeValue(forKey: widgetID) { securityScopedAccess.release(token) }
    }

    private func resolveMediaAccess(for model: inout WidgetModel) {
        guard let bookmarkData = model.mediaBookmarkData else {
            acquireWidgetAccess(model.imageURL, widgetID: model.id)
            model.mediaBookmarkData = MediaLibrarySupport.bookmarkOrLog(for: model.imageURL)
            return
        }
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: bookmarkData, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
            acquireWidgetAccess(url, widgetID: model.id)
            model.imageURL = url
            if stale { model.mediaBookmarkData = MediaLibrarySupport.bookmarkOrLog(for: url) }
        } catch {
            acquireWidgetAccess(model.imageURL, widgetID: model.id)
            print("[Persistence] Media bookmark resolve failed: \(error.localizedDescription)")
        }
    }

    private func supportsMedia(at url: URL) -> Bool {
        if MediaLibrarySupport.supports(url) { return true }
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .png)
            || type.conforms(to: .jpeg)
            || type.conforms(to: .heic)
            || type.conforms(to: .gif)
            || type.conforms(to: .mpeg4Movie)
            || type.conforms(to: .quickTimeMovie)
    }

    private func mediaIsAvailable(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
            && FileManager.default.isReadableFile(atPath: url.path)
    }

    private func validatedModel(from model: WidgetModel) -> WidgetModel {
        var model = model
        // Small portrait and landscape widgets are valid. Clamping each axis
        // independently on restart changes their saved size and aspect ratio.
        if !model.size.width.isFinite || !model.size.height.isFinite
            || model.size.width <= 0 || model.size.height <= 0 {
            model.size = CGSize(width: 300, height: 200)
        }

        let frame = NSRect(origin: model.position, size: model.size)
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
            model.position = centeredPosition(for: model.size)
        }
        return model
    }

    private func centeredPosition(for size: CGSize) -> CGPoint {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return CGPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2
        )
    }
}
