//
//  DesktopWidgetWindow.swift
//  BetterWidgets
//

import AppKit
import CoreGraphics
import SwiftUI

final class DesktopWidgetWindow: NSPanel, NSWindowDelegate {
    var onClose: (() -> Void)?
    var onFrameChange: ((NSRect) -> Void)?
    var onInteractionEnded: (() -> Void)?

    private var hostingView: NSHostingView<WidgetView>!
    private var videoPlaybackController: VideoPlaybackController?
    private var currentModel: WidgetModel
    private(set) var widgetAspectRatio: CGFloat
    private var minimumWidth: CGFloat
    private var isEditMode: Bool
    private var isSelected = false
    private let onReplaceImage: () -> Void
    private let onToggleMute: () -> Void
    private let onDelete: () -> Void

    private enum ResizeAxis {
        case horizontal
        case vertical
    }

    init(
        model: WidgetModel,
        isEditMode: Bool,
        onReplaceImage: @escaping () -> Void,
        onToggleMute: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        let frame = NSRect(origin: model.position, size: model.size)
        let ratio = max(model.size.width / max(model.size.height, 1), 0.01)
        widgetAspectRatio = ratio
        minimumWidth = min(max(120, 80 * ratio), model.size.width)
        self.isEditMode = isEditMode
        self.currentModel = model
        self.onReplaceImage = onReplaceImage
        self.onToggleMute = onToggleMute
        self.onDelete = onDelete
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = true
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        minSize = NSSize(width: minimumWidth, height: minimumWidth / widgetAspectRatio)
        delegate = self
        videoPlaybackController = makeVideoPlaybackController(for: model)
        hostingView = NSHostingView(rootView: makeWidgetView(for: model))
        hostingView.sizingOptions = []
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 16
        contentView = hostingView
        applyWindowConfiguration()
    }

    func updateResizeAspectRatio(for size: CGSize) {
        guard size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return }
        widgetAspectRatio = size.width / size.height
        minimumWidth = min(max(120, 80 * widgetAspectRatio), size.width, frame.width)
        minSize = NSSize(width: minimumWidth, height: minimumWidth / widgetAspectRatio)
    }

    func updateMedia(_ model: WidgetModel) {
        videoPlaybackController?.stop()
        videoPlaybackController = makeVideoPlaybackController(for: model)
        currentModel = model
        hostingView.rootView = makeWidgetView(for: model)
    }

    func updateMute(_ isMuted: Bool) {
        currentModel.isMuted = isMuted
        videoPlaybackController?.setMuted(isMuted)
    }

    func setEditMode(_ isEnabled: Bool) {
        guard isEditMode != isEnabled else { return }

        isEditMode = isEnabled
        applyWindowConfiguration()
    }

    func setSelected(_ isSelected: Bool) {
        self.isSelected = isSelected
        updateEditBorder()
    }

    func windowDidMove(_ notification: Notification) {
        onFrameChange?(frame)
    }

    func windowDidResize(_ notification: Notification) {
        onFrameChange?(frame)
    }

    override func sendEvent(_ event: NSEvent) {
        guard isEditMode else {
            super.sendEvent(event)
            return
        }

        if event.type == .rightMouseDown {
            let menu = makeContextMenu()
            hostingView.menu = menu
            NSMenu.popUpContextMenu(menu, with: event, for: hostingView)
            return
        }

        if event.type == .leftMouseDown, let corner = resizeCorner(for: event) {
            resize(startingWith: event, corner: corner)
            onInteractionEnded?()
            return
        }

        if event.type == .leftMouseDown {
            performDrag(with: event)
            onInteractionEnded?()
            return
        }
        super.sendEvent(event)
    }

    override func close() {
        let completion = onClose
        onClose = nil
        releaseMediaContent()
        super.close()
        completion?()
    }

    func closeWithoutNotifyingManager() {
        onClose = nil
        releaseMediaContent()
        super.close()
    }

    private func releaseMediaContent() {
        videoPlaybackController?.stop()
        videoPlaybackController = nil
        // A closed NSPanel may stay alive in AppKit or in a caller. Detach the
        // hosted views immediately so GIF timers and AVPlayerLayers stop too.
        contentView = nil
        hostingView = nil
        onFrameChange = nil
        onInteractionEnded = nil
        delegate = nil
    }

    private func applyWindowConfiguration() {
        if isEditMode {
            level = .normal
            collectionBehavior = []
            ignoresMouseEvents = false
            updateEditBorder()
            hostingView.menu = makeContextMenu()
        } else {
            level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
            collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            ignoresMouseEvents = true
            hostingView.layer?.borderWidth = 0
            hostingView.menu = nil
        }
    }

    private func updateEditBorder() {
        guard isEditMode else {
            hostingView.layer?.borderWidth = 0
            return
        }

        hostingView.layer?.borderWidth = isSelected ? 2 : 1
        hostingView.layer?.borderColor = (isSelected
            ? NSColor.controlAccentColor
            : NSColor.white.withAlphaComponent(0.45)
        ).cgColor
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        let replaceItem = NSMenuItem(
            title: "Replace Image",
            action: #selector(replaceImage),
            keyEquivalent: ""
        )
        replaceItem.target = self
        menu.addItem(replaceItem)

        if currentModel.mediaType == .video {
            let title = currentModel.isMuted ? "Unmute" : "Mute"
            let muteItem = NSMenuItem(title: title, action: #selector(toggleMute), keyEquivalent: "")
            muteItem.target = self
            menu.addItem(muteItem)
        }

        menu.addItem(.separator())

        let deleteItem = NSMenuItem(
            title: "Delete Widget",
            action: #selector(deleteWidget),
            keyEquivalent: ""
        )
        deleteItem.target = self
        menu.addItem(deleteItem)
        return menu
    }

    @objc private func replaceImage() {
        onReplaceImage()
    }

    @objc private func toggleMute() {
        onToggleMute()
    }

    @objc private func deleteWidget() {
        onDelete()
    }

    private func makeWidgetView(for model: WidgetModel) -> WidgetView {
        WidgetView(model: model, videoPlaybackController: videoPlaybackController)
    }

    private func makeVideoPlaybackController(for model: WidgetModel) -> VideoPlaybackController? {
        guard model.mediaType == .video else { return nil }
        return VideoPlaybackController(url: model.imageURL, isMuted: model.isMuted)
    }

    private func resize(startingWith _: NSEvent, corner: WidgetResizeCorner) {
        let initialFrame = frame
        let initialMouseLocation = NSEvent.mouseLocation
        let anchor = oppositeAnchor(for: corner, in: initialFrame)
        var dominantAxis: ResizeAxis?

        while let nextEvent = NSApp.nextEvent(
            matching: [.leftMouseDragged, .leftMouseUp],
            until: .distantFuture,
            inMode: .eventTracking,
            dequeue: true
        ) {
            if nextEvent.type == .leftMouseUp {
                onFrameChange?(frame)
                return
            }

            let currentMouseLocation = NSEvent.mouseLocation
            let horizontalChange = corner.isLeft
                ? initialMouseLocation.x - currentMouseLocation.x
                : currentMouseLocation.x - initialMouseLocation.x
            let verticalChange = corner.isTop
                ? currentMouseLocation.y - initialMouseLocation.y
                : initialMouseLocation.y - currentMouseLocation.y

            if dominantAxis == nil, horizontalChange != 0 || verticalChange != 0 {
                dominantAxis = abs(horizontalChange) >= abs(verticalChange * widgetAspectRatio)
                    ? .horizontal
                    : .vertical
            }

            let widthChange: CGFloat
            switch dominantAxis ?? .horizontal {
            case .horizontal:
                widthChange = horizontalChange
            case .vertical:
                widthChange = verticalChange * widgetAspectRatio
            }
            let newWidth = max(minimumWidth, initialFrame.width + widthChange)
            let newHeight = newWidth / widgetAspectRatio

            setFrame(
                frame(for: corner, anchor: anchor, width: newWidth, height: newHeight),
                display: true
            )
        }
    }

    private func resizeCorner(for event: NSEvent) -> WidgetResizeCorner? {
        let location = convertPoint(toScreen: event.locationInWindow)
        let cornerSize: CGFloat = 20
        let nearLeft = abs(location.x - frame.minX) <= cornerSize
        let nearRight = abs(location.x - frame.maxX) <= cornerSize
        let nearBottom = abs(location.y - frame.minY) <= cornerSize
        let nearTop = abs(location.y - frame.maxY) <= cornerSize
        if nearLeft && nearTop { return .topLeft }
        if nearRight && nearTop { return .topRight }
        if nearLeft && nearBottom { return .bottomLeft }
        if nearRight && nearBottom { return .bottomRight }
        return nil
    }

    private func oppositeAnchor(for corner: WidgetResizeCorner, in frame: NSRect) -> NSPoint {
        switch corner {
        case .topLeft:
            return NSPoint(x: frame.maxX, y: frame.minY)
        case .topRight:
            return NSPoint(x: frame.minX, y: frame.minY)
        case .bottomLeft:
            return NSPoint(x: frame.maxX, y: frame.maxY)
        case .bottomRight:
            return NSPoint(x: frame.minX, y: frame.maxY)
        }
    }

    private func frame(
        for corner: WidgetResizeCorner,
        anchor: NSPoint,
        width: CGFloat,
        height: CGFloat
    ) -> NSRect {
        switch corner {
        case .topLeft:
            return NSRect(x: anchor.x - width, y: anchor.y, width: width, height: height)
        case .topRight:
            return NSRect(x: anchor.x, y: anchor.y, width: width, height: height)
        case .bottomLeft:
            return NSRect(x: anchor.x - width, y: anchor.y - height, width: width, height: height)
        case .bottomRight:
            return NSRect(x: anchor.x, y: anchor.y - height, width: width, height: height)
        }
    }
}
