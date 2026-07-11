import Foundation

/// Stores playlists as JSON in Application Support/Konpo/playlists.json.
@MainActor
@Observable
final class PlaylistStore {
    private(set) var playlists: [Playlist] = []
    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("Konpo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("playlists.json")
        load()
    }

    @discardableResult
    func create(name: String) -> Playlist {
        let playlist = Playlist(name: name)
        playlists.append(playlist)
        save()
        return playlist
    }

    func addTrack(_ url: URL, to id: Playlist.ID) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        if !playlists[index].trackPaths.contains(url.path) {
            playlists[index].trackPaths.append(url.path)
            save()
        }
    }

    /// Append many tracks with a single save (for "add folder"), skipping dupes.
    func addTracks(_ urls: [URL], to id: Playlist.ID) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        var seen = Set(playlists[index].trackPaths)
        for url in urls where seen.insert(url.path).inserted {
            playlists[index].trackPaths.append(url.path)
        }
        save()
    }

    func removeTrack(_ url: URL, from id: Playlist.ID) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[index].trackPaths.removeAll { $0 == url.path }
        save()
    }

    func delete(_ id: Playlist.ID) {
        playlists.removeAll { $0.id == id }
        save()
    }

    func rename(_ id: Playlist.ID, to name: String) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[index].name = name
        save()
    }

    func urls(for id: Playlist.ID) -> [URL] {
        guard let playlist = playlists.first(where: { $0.id == id }) else { return [] }
        return playlist.trackPaths.map { URL(fileURLWithPath: $0) }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Playlist].self, from: data) else { return }
        playlists = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(playlists) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
