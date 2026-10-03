import Foundation
import UniformTypeIdentifiers

struct MediaFolder: Codable, Identifiable, Hashable {
    let id: UUID
    var displayName: String
    var bookmarkData: Data
    var lastKnownURL: URL?
}

struct MediaItem: Identifiable, Hashable, Sendable {
    let id: String
    let folderID: UUID
    let url: URL
    let name: String
    let mediaType: WidgetMediaType

    nonisolated init(folderID: UUID, url: URL) {
        self.folderID = folderID
        self.url = url
        self.name = url.lastPathComponent
        self.mediaType = WidgetMediaType.mediaType(for: url)
        self.id = "\(folderID.uuidString):\(url.standardizedFileURL.path)"
    }
}

enum MediaLibrarySupport {
    nonisolated static let extensions: Set<String> = ["png", "jpg", "jpeg", "heic", "gif", "mp4", "mov"]

    nonisolated static func supports(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }

    static func bookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    static func bookmarkOrLog(for url: URL) -> Data? {
        do { return try bookmark(for: url) }
        catch {
            print("[Persistence] Bookmark save failed for \(url.path): \(error.localizedDescription)")
            return nil
        }
    }

    static func resolve(_ folder: MediaFolder) -> (URL, Bool)? {
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: folder.bookmarkData, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
            return (url, stale)
        } catch {
            print("[Persistence] Folder bookmark resolve failed: \(error.localizedDescription)")
            return folder.lastKnownURL.map { ($0, false) }
        }
    }

    nonisolated static func scan(_ url: URL, folderID: UUID) -> [MediaItem] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        return urls.filter {
            supports($0) && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }.map { MediaItem(folderID: folderID, url: $0) }
    }
}
