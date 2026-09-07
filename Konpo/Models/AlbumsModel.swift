import Foundation

/// The album-grid's own state: what was discovered under the current folder
/// scope, the live search text, and which album is playing.
///
/// Split out of AppModel, which was coordinating browsing, playback, playlists
/// and Now Playing as well. Discovery is a filesystem walk with its own cache
/// and cancellation, and none of it is entangled with the rest.
@MainActor
@Observable
final class AlbumsModel {

    /// Albums under the folder currently selected in the tree.
    private(set) var items: [Album] = []
    private(set) var isLoading = false

    /// The album whose tracks are loaded (played from the grid). Drives the
    /// album-view art panel's header and tracklist; nil when the loaded tracks
    /// came from a folder or a playlist instead.
    var playing: Album?

    /// Live filter text for the grid.
    var searchText = ""
    /// Bumped by the Find command (⌘F) to ask the grid to focus its search field.
    var searchFocusRequest = 0

    private var task: Task<Void, Never>?
    /// Discovered albums per folder scope. Bounded because each entry holds every
    /// track URL under that folder, and browsing around a large library would
    /// otherwise accumulate them all for the life of the session.
    private var cache = LRUCache<URL, [Album]>(costLimit: 8)

    /// Discover the albums under `url` (recursively). The walk runs off the main
    /// actor; the grid renders thumbnails lazily so only visible covers load.
    func load(for url: URL?) {
        task?.cancel()
        guard let url else { items = []; isLoading = false; return }
        if let cached = cache[url] { items = cached; isLoading = false; return }
        isLoading = true
        items = []
        task = Task {
            let found = await Task.detached(priority: .userInitiated) {
                FileTreeModel.albumFolders(under: url)
            }.value
            if Task.isCancelled { return }
            cache.set(found, forKey: url)
            items = found
            isLoading = false
        }
    }

    /// Drop the cache so ⌘R re-walks from disk.
    func invalidate() {
        cache.removeAll()
    }
}
