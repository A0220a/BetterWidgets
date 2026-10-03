import Foundation

/// Share one sandbox extension between owners and balance only successful starts.
final class SecurityScopedAccessPool {
    private struct Entry {
        var owners: Int
        var scopedURL: URL?
    }

    private var entries: [String: Entry] = [:]
    private var owners: [UUID: String] = [:]
    private let start: (URL) -> Bool
    private let stop: (URL) -> Void

    init(
        start: @escaping (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
        stop: @escaping (URL) -> Void = { $0.stopAccessingSecurityScopedResource() }
    ) {
        self.start = start
        self.stop = stop
    }

    func acquire(_ url: URL) -> UUID {
        let key = url.standardizedFileURL.absoluteString
        var entry = entries[key] ?? Entry(owners: 0, scopedURL: nil)
        // A previously unscoped URL may later arrive with a valid bookmark.
        if entry.scopedURL == nil, start(url) {
            entry.scopedURL = url
        }
        entry.owners += 1
        entries[key] = entry
        let owner = UUID()
        owners[owner] = key
        return owner
    }

    func release(_ owner: UUID) {
        // A bookmarked URL can resolve to a new path after a move. Use the
        // stable acquisition token rather than recomputing its dictionary key.
        guard let key = owners.removeValue(forKey: owner), var entry = entries[key] else { return }
        entry.owners -= 1
        if entry.owners == 0 {
            entries[key] = nil
            if let scopedURL = entry.scopedURL { stop(scopedURL) }
        } else {
            entries[key] = entry
        }
    }

    func releaseAll() {
        let scopedURLs = entries.values.compactMap(\.scopedURL)
        entries.removeAll()
        owners.removeAll()
        scopedURLs.forEach(stop)
    }

    deinit {
        entries.values.compactMap(\.scopedURL).forEach(stop)
    }
}
