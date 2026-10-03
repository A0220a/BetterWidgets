import SwiftUI
import UniformTypeIdentifiers

private enum LibraryLayout {
    static let cardScale: CGFloat = 0.5
    static let spacing: CGFloat = 16 * cardScale
    static let columns = [GridItem(.adaptive(minimum: 180 * cardScale), spacing: spacing)]
    static let footerHeight: CGFloat = 78 * cardScale
    static let cornerRadius: CGFloat = 16 * cardScale
}

struct ContentView: View {
    @ObservedObject var widgetManager: WidgetManager
    var onShowAbout: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if widgetManager.isEditMode {
                Label("Drag desktop widgets to move them, or drag their corners to resize.", systemImage: "cursorarrow.and.square.on.square.dashed")
                    .font(.callout)
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.accentColor.opacity(0.08))
            }

            if let error = widgetManager.persistenceError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    WidgetSection(manager: widgetManager)

                    if !widgetManager.folders.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 20) {
                            SectionHeading(
                                title: "Media Library",
                                subtitle: "Choose media from your folders to add to the desktop.",
                                count: widgetManager.folders.count
                            )
                            ForEach(widgetManager.folders) { folder in
                                FolderSection(folder: folder, manager: widgetManager)
                            }
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            HStack(spacing: 12) {
                AddFolderButton(manager: widgetManager)
                Text("Images, GIFs & videos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                AddWidgetButton(manager: widgetManager)
            }
            .padding(.horizontal, 24)
            .frame(height: 68)
            .background(.bar)
        }
        .frame(minWidth: 640, minHeight: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            widgetManager.refreshMediaAvailability()
            widgetManager.folders.forEach { widgetManager.refreshFolder($0) }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text("BetterWidgets")
                    .font(.title2.weight(.semibold))
                Text("\(widgetManager.desktopWidgetCount) on desktop · \(widgetManager.widgets.count) saved")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let onShowAbout {
                Button(action: onShowAbout) {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("About BetterWidgets")
                .help("About BetterWidgets and how to use it")
            }
            Button {
                widgetManager.setEditMode(!widgetManager.isEditMode)
            } label: {
                Label(
                    widgetManager.isEditMode ? "Done" : "Edit Widgets",
                    systemImage: widgetManager.isEditMode ? "checkmark" : "pencil"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .help(widgetManager.isEditMode ? "Finish moving and resizing desktop widgets" : "Move and resize widgets on the desktop")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(.bar)
    }
}

private struct SectionHeading: View {
    let title: String
    let subtitle: String
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(title).font(.title3.weight(.semibold))
                Text(count, format: .number)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
        }
    }
}

private struct WidgetSection: View {
    @ObservedObject var manager: WidgetManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(
                title: "Your Widgets",
                subtitle: "Everything saved for your desktop, in one place.",
                count: manager.widgets.count
            )
            if manager.widgets.isEmpty {
                LibraryEmptyState(
                    symbol: "square.grid.2x2",
                    title: "Make your desktop yours",
                    message: "Add an image, GIF, or video, or browse a media folder."
                )
            } else {
                LazyVGrid(columns: LibraryLayout.columns, spacing: LibraryLayout.spacing) {
                    ForEach(manager.widgets) { model in
                        WidgetCard(model: model, manager: manager)
                    }
                }
            }
        }
    }
}

private struct WidgetCard: View {
    let model: WidgetModel
    @ObservedObject var manager: WidgetManager
    private var isUnavailable: Bool { manager.isMediaUnavailable(for: model.id) }

    var body: some View {
        MediaCard(
            name: model.imageURL.lastPathComponent,
            mediaType: model.mediaType,
            thumbnail: WidgetThumbnailView(model: model),
            isUnavailable: isUnavailable,
            isSelected: manager.selectedWidgetID == model.id,
            select: { manager.selectWidget(withID: model.id) }
        ) {
            WidgetCardActions(model: model, manager: manager)
        } controls: {
            if isUnavailable {
                Button { manager.replaceWidget(withID: model.id) } label: {
                    Label("Replace File", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 8, weight: .medium))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel("Replace unavailable file: \(model.imageURL.lastPathComponent)")
                .help("Choose a replacement for the unavailable file")
            } else {
                desktopControls
            }
        }
    }

    private var desktopControls: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(model.isEnabled ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 3, height: 3)
            Text(model.isEnabled ? "On Desktop" : "Hidden")
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 2)
            Toggle(
                "Show \(model.imageURL.lastPathComponent) on desktop",
                isOn: Binding(
                    get: { model.isEnabled },
                    set: { manager.setEnabled($0, for: model.id) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .scaleEffect(0.75)
            .frame(width: 24, height: 12)
            .help(model.isEnabled ? "Hide this widget from the desktop" : "Show this widget on the desktop")
        }
    }
}

/// Both libraries share the same square footprint, preview, and control positions.
private struct MediaCard<Actions: View, Controls: View>: View {
    let name: String
    let mediaType: WidgetMediaType
    let thumbnail: WidgetThumbnailView
    var isUnavailable = false
    var isSelected = false
    var select: (() -> Void)? = nil
    @ViewBuilder let actions: () -> Actions
    @ViewBuilder let controls: () -> Controls
    @State private var isHovered = false

    var body: some View {
        GeometryReader { geometry in
            let previewHeight = max(0, geometry.size.height - LibraryLayout.footerHeight)
            VStack(spacing: 0) {
                // Scale the native thumbnail's original canvas as well as its
                // frame, so reducing the card does not change its cropping.
                preview
                    .frame(
                        width: geometry.size.width / LibraryLayout.cardScale,
                        height: previewHeight / LibraryLayout.cardScale
                    )
                    .scaleEffect(LibraryLayout.cardScale)
                    .frame(width: geometry.size.width, height: previewHeight)
                    .clipped()
                    .overlay(alignment: .top) {
                        HStack(alignment: .top, spacing: 3) {
                            Text(mediaType.title)
                                .font(.system(size: 8, weight: .semibold))
                                .padding(.horizontal, 4)
                                .frame(height: 18)
                                .background(.regularMaterial, in: Capsule())
                            Spacer(minLength: 0)
                            actions()
                        }
                        .padding(5)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    if let select {
                        Button(action: select) { filename }
                            .buttonStyle(.plain)
                            .help("Select \(name)")
                    } else {
                        filename
                    }
                    controls().frame(height: 12)
                }
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: LibraryLayout.footerHeight)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: LibraryLayout.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: LibraryLayout.cornerRadius)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.primary.opacity(isHovered ? 0.18 : 0.08),
                        lineWidth: isSelected ? 1 : 0.5
                    )
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(isHovered ? 0.08 : 0.03), radius: 3, y: 1)
        }
        .aspectRatio(1, contentMode: .fit)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder private var preview: some View {
        if isUnavailable {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 32))
                Text("File unavailable")
                    .font(.system(size: 14))
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.secondary.opacity(0.08))
            .accessibilityElement(children: .combine)
        } else if let select {
            Button(action: select) { thumbnail }
                .buttonStyle(.plain)
                .accessibilityLabel("Select \(name)")
                .help("Select this desktop widget")
        } else {
            thumbnail
                .accessibilityLabel(name)
        }
    }

    private var filename: some View {
        Text(displayName)
            .font(.system(size: 9, weight: .medium))
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(name)
    }

    private var displayName: String {
        let stem = (name as NSString).deletingPathExtension
        // A file named only ".gif" has no stem; keep its card title visible.
        if stem.isEmpty || (name.hasPrefix(".") && MediaLibrarySupport.extensions.contains(String(name.dropFirst()).lowercased())) {
            return "Untitled"
        }
        return stem
    }
}

private struct WidgetCardActions: View {
    let model: WidgetModel
    let manager: WidgetManager

    var body: some View {
        HStack(spacing: 3) {
            if model.mediaType == .video, !manager.isMediaUnavailable(for: model.id) {
                Button {
                    manager.toggleMute(for: model.id)
                } label: {
                    Image(systemName: model.isMuted ? "speaker.slash" : "speaker.wave.2")
                        .font(.system(size: 9))
                        .frame(width: 20, height: 18)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.isMuted ? "Unmute \(model.imageURL.lastPathComponent)" : "Mute \(model.imageURL.lastPathComponent)")
                .help(model.isMuted ? "Unmute video" : "Mute video")
            }
            Menu {
                Button("Replace", systemImage: "arrow.triangle.2.circlepath") {
                    manager.replaceWidget(withID: model.id)
                }
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive) {
                    manager.deleteWidget(withID: model.id)
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .font(.system(size: 9))
            .frame(width: 20, height: 18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
            .accessibilityLabel("Actions for \(model.imageURL.lastPathComponent)")
            .help("Widget actions")
        }
    }
}

private struct FolderSection: View {
    let folder: MediaFolder
    @ObservedObject var manager: WidgetManager
    private var items: [MediaItem] { manager.mediaItems[folder.id] ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 3) {
                    Text(folder.displayName).font(.headline).lineLimit(1).help(folder.displayName)
                    Text("\(items.count) media files").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { manager.refreshFolder(folder) } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Refresh \(folder.displayName)")
                .help("Refresh folder")
                Menu {
                    Button("Remove Folder", systemImage: "folder.badge.minus", role: .destructive) {
                        manager.removeFolder(folder)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 24, height: 24)
                .accessibilityLabel("Actions for \(folder.displayName)")
                .help("Folder actions")
            }

            if items.isEmpty {
                LibraryEmptyState(
                    symbol: "photo.on.rectangle.angled",
                    title: "No supported media files",
                    message: "Add images, GIFs, or videos to this folder, then refresh it."
                )
            } else {
                LazyVGrid(columns: LibraryLayout.columns, spacing: LibraryLayout.spacing) {
                    ForEach(items) { item in
                        MediaItemCard(item: item, manager: manager)
                    }
                }
            }
        }
    }
}

private struct MediaItemCard: View {
    let item: MediaItem
    @ObservedObject var manager: WidgetManager
    private var widget: WidgetModel? { manager.widgets.first { $0.mediaItemKey == item.id } }
    private var isEnabled: Bool { widget?.isEnabled == true }

    var body: some View {
        MediaCard(
            name: item.name,
            mediaType: item.mediaType,
            thumbnail: WidgetThumbnailView(item: item),
            isSelected: widget.map { manager.selectedWidgetID == $0.id } ?? false
        ) {
            if let widget {
                WidgetCardActions(model: widget, manager: manager)
            }
        } controls: {
            Button { manager.toggleMediaItem(item) } label: {
                HStack(spacing: 3) {
                    Image(systemName: isEnabled ? "checkmark.circle.fill" : "plus")
                    Text(isEnabled ? "Hide from Desktop" : "Add to Desktop")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .font(.system(size: 8, weight: .medium))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    isEnabled ? Color.secondary.opacity(0.1) : Color.accentColor.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 3)
                )
            }
            .buttonStyle(.plain)
            .foregroundStyle(isEnabled ? Color.primary : Color.accentColor)
            .accessibilityLabel("\(isEnabled ? "Hide from desktop" : "Add to desktop"): \(item.name)")
            .help(isEnabled ? "Hide this widget from the desktop" : "Add this file as a desktop widget")
        }
    }
}

private struct LibraryEmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 28)).foregroundStyle(.tertiary)
            Text(title).font(.headline)
            Text(message).font(.callout).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 20)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct AddFolderButton: View {
    let manager: WidgetManager

    var body: some View {
        Button { manager.addFolder() } label: {
            Label("Add Folder", systemImage: "folder.badge.plus")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .help("Browse images, GIFs, and videos from a folder")
    }
}

private struct AddWidgetButton: View {
    @ObservedObject var manager: WidgetManager

    var body: some View {
        Button { manager.addWidget() } label: {
            Label(manager.isMediaDropTarget ? "Drop to Add" : "Add Widget", systemImage: "plus")
                .frame(minWidth: 116, minHeight: 24)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .help("Choose a media file, or drop one onto this button")
        .onDrop(
            of: [UTType.fileURL.identifier],
            isTargeted: Binding(
                get: { manager.isMediaDropTarget },
                set: { manager.setMediaDropTarget($0) }
            )
        ) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in manager.createWidget(from: url) }
            }
            return true
        }
    }
}

private extension WidgetMediaType {
    var title: String {
        switch self {
        case .image: "Image"
        case .gif: "GIF"
        case .video: "Video"
        }
    }
}
