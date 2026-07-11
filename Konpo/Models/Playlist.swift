import Foundation

/// A user playlist: an ordered list of track file paths (paths, not bookmarks,
/// since the app is non-sandboxed).
struct Playlist: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var trackPaths: [String]

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.trackPaths = []
    }
}
