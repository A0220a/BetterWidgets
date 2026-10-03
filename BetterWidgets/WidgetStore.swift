//
//  WidgetStore.swift
//  BetterWidgets
//

import Foundation

final class WidgetStore {
    private let fileManager: FileManager
    private let fileURL: URL

    init(fileManager: FileManager = .default, fileURL: URL? = nil) {
        self.fileManager = fileManager
        let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directoryURL = applicationSupportURL.appendingPathComponent("BetterWidgets", isDirectory: true)
        self.fileURL = fileURL ?? directoryURL.appendingPathComponent("widgets.json")
        print("[Persistence] URL: \(self.fileURL.path)")
    }

    struct Snapshot: Codable {
        var widgets: [WidgetModel]
        var folders: [MediaFolder]

        init(widgets: [WidgetModel], folders: [MediaFolder]) {
            self.widgets = widgets
            self.folders = folders
        }

        private enum CodingKeys: String, CodingKey { case widgets, folders }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            widgets = try container.decode([WidgetModel].self, forKey: .widgets)
            folders = try container.decodeIfPresent([MediaFolder].self, forKey: .folders) ?? []
        }
    }

    func load() throws -> Snapshot {
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            let snapshot: Snapshot
            if let widgets = try? decoder.decode([WidgetModel].self, from: data) {
                snapshot = Snapshot(widgets: widgets, folders: [])
            } else {
                snapshot = try decoder.decode(Snapshot.self, from: data)
            }
            // Duplicate identities would overwrite the manager's dictionaries
            // while leaving the earlier windows and sandbox leases alive.
            guard Set(snapshot.widgets.map(\.id)).count == snapshot.widgets.count,
                  Set(snapshot.folders.map(\.id)).count == snapshot.folders.count else {
                throw CocoaError(.fileReadCorruptFile)
            }
            print("[Persistence] Loaded \(snapshot.widgets.count) widgets")
            return snapshot
        } catch CocoaError.fileReadNoSuchFile {
            print("[Persistence] Loaded 0 widgets; file does not exist")
            return Snapshot(widgets: [], folders: [])
        }
    }

    func save(widgets: [WidgetModel], folders: [MediaFolder]) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Snapshot(widgets: widgets, folders: folders))
        try data.write(to: fileURL, options: .atomic)
        print("[Persistence] Saved \(widgets.count) widgets, \(folders.count) folders")
    }
}
