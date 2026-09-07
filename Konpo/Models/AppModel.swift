import Foundation
import AppKit

/// Composition root. Owns the folder tree, player, metadata, and Now Playing
/// bridge, plus the current folder/track selection and the play queue.
@MainActor
@Observable
final class AppModel {
    let tree = FileTreeModel()
    let player = PlayerEngine()
    let metadata = MetadataService()
    let playlists = PlaylistStore()
    let appearance = Appearance()
    let albums = AlbumsModel()
    @ObservationIgnored let nowPlayingService = NowPlayingService()

    /// The three top-level views: the folder tree + track list, the album grid,
    /// and playlists. Folders and albums share the folder-tree sidebar; playlists
    /// swaps it for the playlist list.
    enum ViewMode: String { case folders, albums, playlists }

    var selectedFolder: FileNode?
    var tracks: [Track] = []
    var selectedTrack: Track?
    var nowPlaying: Track?
    /// Transient error banner text (auto-clears).
    var errorMessage: String?

    // View mode / playlists
    var viewMode: ViewMode = .folders {
        didSet { Defaults.viewMode = viewMode.rawValue }
    }
    var selectedPlaylist: Playlist?
    var showNewPlaylistPrompt = false
    var newPlaylistName = ""


    /// Track whose album art the full-size art window should display.
    var artworkFullURL: URL?

    /// Optional user folder of visualizer presets (.milk or .json). nil = built-in.
    var visualizerPresetFolder: String? {
        didSet {
            Defaults.visualizerPresetFolder = visualizerPresetFolder
        }
    }

    private enum PendingPlaylistAdd { case none, track(URL), folder(URL) }
    private var pendingAdd: PendingPlaylistAdd = .none

    /// What playback is stepping through. Separate from `tracks` (what the
    /// centre pane is showing) so browsing never disturbs a queue that came
    /// from somewhere else.
    private var queue = PlayQueue()

    private var loadTracksTask: Task<Void, Never>?
    private var errorClearTask: Task<Void, Never>?
    private var nowPlayingArt: NSImage?
    private var nowPlayingArtURL: URL?

    init() {
        visualizerPresetFolder = Defaults.visualizerPresetFolder
        player.onTrackChanged = { [weak self] url in self?.engineAdvanced(to: url) }
        player.onPlaybackEnded = { [weak self] in self?.playbackEnded() }
        player.onError = { [weak self] message in self?.showError(message) }
        player.onTrackFailed = { [weak self] url in self?.skipFailedTrack(url) }
        playlists.onError = { [weak self] message in self?.showError(message) }
        wireRemoteCommands()
        restoreSession()
    }

    // MARK: - Browsing

    func chooseRoot() {
        tree.chooseRoot()
        if let root = tree.root {
            selectFolder(root)
        }
    }

    func chooseVisualizerPresetFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        panel.message = "Choose a folder of MilkDrop (.milk) or Butterchurn (.json) presets"
        if panel.runModal() == .OK, let url = panel.url {
            visualizerPresetFolder = url.path
        }
    }

    func useBuiltInVisualizerPresets() { visualizerPresetFolder = nil }

    func selectFolder(_ node: FileNode) {
        selectedFolder = node
        selectedTrack = nil
        Defaults.lastFolderPath = node.url.path
        if viewMode == .albums {
            albums.load(for: node.url)
        } else {
            loadTracks(from: node.url)
        }
    }

    // MARK: - Album grid

    /// Jukebox play: queue the album's tracks and start from the first. The tree
    /// selection (the album grid's scope) is left untouched.
    func playAlbum(_ album: Album) {
        let queue = album.trackURLs.map { Track(url: $0) }
        guard let first = queue.first else { return }
        albums.playing = album
        tracks = queue
        selectedTrack = first
        loadTracksTask?.cancel()
        play(first, in: queue)
        // Files often aren't named in track order, so once tags load, reorder the
        // album by disc + track number. If that reveals a different opening track
        // and we're still at the very start, begin from the real first track.
        var discIndex: [URL: Int] = [:]
        for (i, disc) in album.discs.enumerated() {
            for url in disc.trackURLs { discIndex[url] = i }
        }
        loadTracksTask = Task {
            await loadMetadata(for: queue)
            if Task.isCancelled { return }
            let atStart = nowPlaying?.url == first.url && player.position < 3
            sortTracksByNumber(discIndex: discIndex)
            if atStart, let realFirst = tracks.first, realFirst.url != first.url {
                play(realFirst, in: tracks)
            }
        }
    }

    /// Reorder `tracks` by disc (when a map is given), then tag track number, with
    /// filename as the tie-break / fallback. Keeps the play queue and current
    /// track in sync when the queue is this same collection (so folder browsing
    /// never disturbs playback coming from elsewhere).
    private func sortTracksByNumber(discIndex: [URL: Int]? = nil) {
        let sorted = tracks.sorted { a, b in
            if let discIndex {
                let da = discIndex[a.url] ?? 0, db = discIndex[b.url] ?? 0
                if da != db { return da < db }
            }
            if let x = a.trackNumber, let y = b.trackNumber, x != y { return x < y }
            if (a.trackNumber == nil) != (b.trackNumber == nil) { return a.trackNumber != nil }
            return a.url.lastPathComponent.localizedStandardCompare(b.url.lastPathComponent) == .orderedAscending
        }
        tracks = sorted
        // Only re-orders the queue when it holds this same set of tracks, so a
        // folder re-sort can't reach into playback started from elsewhere.
        if queue.reorder(to: sorted) {
            player.setUpcoming(url: queue.upcoming?.url)
        }
    }

    /// On launch, restore the view mode plus the last folder/playlist.
    private func restoreSession() {
        let savedMode = ViewMode(rawValue: Defaults.viewMode ?? "") ?? .folders
        // The mode is restored even with no music folder open — playlists work
        // without one, and this used to bail before restoring anything.
        viewMode = savedMode
        guard tree.root != nil else {
            if savedMode == .playlists { restoreLastPlaylist() }
            return
        }
        Task {
            // Resolve the last folder node so switching back to Folders works.
            let lastPath = Defaults.lastFolderPath
            let node: FileNode?
            if let lastPath {
                node = await tree.revealFolder(at: URL(fileURLWithPath: lastPath, isDirectory: true)) ?? tree.root
            } else {
                node = tree.root
            }
            selectedFolder = node
            viewMode = savedMode

            if savedMode == .playlists {
                restoreLastPlaylist()
            } else if let node {
                selectFolder(node)
            }
        }
    }

    private func restoreLastPlaylist() {
        guard let idString = Defaults.lastPlaylistID,
              let id = UUID(uuidString: idString),
              let playlist = playlists.playlists.first(where: { $0.id == id }) else { return }
        selectPlaylist(playlist)
    }

    /// ⌘R: re-read the current folder's subfolders, tracks, and albums from disk.
    func refresh() {
        guard let folder = selectedFolder else { return }
        Task {
            await metadata.clearCache()
            await tree.refresh(folder)
            albums.invalidate()
            if viewMode == .albums {
                albums.load(for: folder.url)
            } else {
                loadTracks(from: folder.url)
            }
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
        errorClearTask?.cancel()
        errorClearTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { errorMessage = nil }
        }
    }

    private func loadTracks(from url: URL) {
        // A folder is an album — order it by track number once tags load.
        startTrackLoad(sortByNumber: true) {
            await Task.detached(priority: .userInitiated) { FileTreeModel.audioFiles(in: url) }.value
        }
    }

    private func loadTracks(urls: [URL]) {
        // Playlists keep their curated order — never re-sort.
        startTrackLoad { urls.map { Track(url: $0) } }
    }

    private func startTrackLoad(sortByNumber: Bool = false, _ produce: @escaping @Sendable () async -> [Track]) {
        albums.playing = nil
        loadTracksTask?.cancel()
        loadTracksTask = Task {
            let files = await produce()
            if Task.isCancelled { return }
            tracks = files
            let autoFirst = files.first
            if selectedTrack == nil { selectedTrack = autoFirst }
            await loadMetadata(for: files)
            if Task.isCancelled { return }
            if sortByNumber {
                sortTracksByNumber()
                // Keep the default selection on the real first track after reordering.
                if selectedTrack?.url == autoFirst?.url { selectedTrack = tracks.first }
            }
        }
    }

    // MARK: - Playlists

    func setViewMode(_ mode: ViewMode) {
        viewMode = mode
        selectedTrack = nil
        switch mode {
        case .folders:
            if let folder = selectedFolder { loadTracks(from: folder.url) } else { tracks = [] }
        case .albums:
            // The grid loads albums itself from the current folder scope.
            albums.load(for: selectedFolder?.url)
        case .playlists:
            if let playlist = selectedPlaylist { selectPlaylist(playlist) } else { tracks = [] }
        }
    }

    func selectPlaylist(_ playlist: Playlist) {
        selectedPlaylist = playlist
        selectedTrack = nil
        Defaults.lastPlaylistID = playlist.id.uuidString
        loadTracks(urls: playlists.urls(for: playlist.id))
    }

    func addToPlaylist(_ track: Track, playlist: Playlist) {
        playlists.addTrack(track.url, to: playlist.id)
        refreshIfViewing(playlist.id)
    }

    /// Add every audio file under a folder (recursively) to a playlist.
    func addFolderToPlaylist(_ node: FileNode, playlist: Playlist) {
        let url = node.url
        let id = playlist.id
        Task {
            let found = await Task.detached(priority: .userInitiated) {
                FileTreeModel.audioFilesRecursive(in: url)
            }.value
            playlists.addTracks(found.map(\.url), to: id)
            refreshIfViewing(id)
        }
    }

    private func refreshIfViewing(_ id: Playlist.ID) {
        if viewMode == .playlists, selectedPlaylist?.id == id,
           let updated = playlists.playlists.first(where: { $0.id == id }) {
            selectPlaylist(updated)
        }
    }

    func removeFromPlaylist(_ track: Track, playlist: Playlist) {
        playlists.removeTrack(track.url, from: playlist.id)
        if let updated = playlists.playlists.first(where: { $0.id == playlist.id }) {
            selectPlaylist(updated)
        }
    }

    func deletePlaylist(_ playlist: Playlist) {
        playlists.delete(playlist.id)
        if selectedPlaylist?.id == playlist.id {
            selectedPlaylist = nil
            tracks = []
            selectedTrack = nil
        }
    }

    func beginNewPlaylist(with track: Track?) {
        pendingAdd = track.map { .track($0.url) } ?? .none
        newPlaylistName = ""
        showNewPlaylistPrompt = true
    }

    func beginNewPlaylist(withFolder node: FileNode) {
        pendingAdd = .folder(node.url)
        newPlaylistName = ""
        showNewPlaylistPrompt = true
    }

    func confirmNewPlaylist() {
        let name = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
        showNewPlaylistPrompt = false
        let pending = pendingAdd
        pendingAdd = .none
        guard !name.isEmpty else { return }
        let playlist = playlists.create(name: name)
        Task {
            await addPending(pending, to: playlist.id)
            viewMode = .playlists
            if let created = playlists.playlists.first(where: { $0.id == playlist.id }) {
                selectPlaylist(created)
            }
        }
    }

    func cancelNewPlaylist() {
        pendingAdd = .none
        showNewPlaylistPrompt = false
    }

    private func addPending(_ pending: PendingPlaylistAdd, to id: Playlist.ID) async {
        switch pending {
        case .none:
            break
        case .track(let url):
            playlists.addTrack(url, to: id)
        case .folder(let url):
            let found = await Task.detached(priority: .userInitiated) {
                FileTreeModel.audioFilesRecursive(in: url)
            }.value
            playlists.addTracks(found.map(\.url), to: id)
        }
    }

    private func loadMetadata(for files: [Track]) async {
        await withTaskGroup(of: (Int, TrackMetadata).self) { group in
            let maxConcurrent = 6
            var next = 0
            while next < files.count && next < maxConcurrent {
                let i = next
                let url = files[i].url
                group.addTask { [metadata] in (i, await metadata.metadata(for: url)) }
                next += 1
            }
            for await (index, meta) in group {
                if Task.isCancelled { break }
                applyMetadata(meta, at: index, expected: files[index].url)
                if next < files.count {
                    let i = next
                    let url = files[i].url
                    group.addTask { [metadata] in (i, await metadata.metadata(for: url)) }
                    next += 1
                }
            }
        }
    }

    private func applyMetadata(_ meta: TrackMetadata, at index: Int, expected url: URL) {
        guard index < tracks.count, tracks[index].url == url else { return }
        tracks[index].apply(meta)
        let updated = tracks[index]
        if selectedTrack?.url == url { selectedTrack = updated }
        if nowPlaying?.url == url { nowPlaying = updated; refreshNowPlaying() }
    }

    // MARK: - Keyboard selection

    func moveSelection(_ delta: Int) {
        guard !tracks.isEmpty else { return }
        let current = selectedTrack.flatMap { t in tracks.firstIndex { $0.url == t.url } } ?? -1
        let target = min(max(current + delta, 0), tracks.count - 1)
        selectedTrack = tracks[target]
    }

    // MARK: - Keyboard folder navigation

    /// The folder tree flattened to its currently-visible (expanded) rows.
    func visibleFolders() -> [FileNode] {
        guard let root = tree.root else { return [] }
        var out: [FileNode] = []
        func walk(_ node: FileNode) {
            out.append(node)
            if node.isExpanded, let children = node.children { children.forEach(walk) }
        }
        walk(root)
        return out
    }

    /// Move the folder selection up/down through the visible tree, loading tracks.
    func moveFolderSelection(_ delta: Int) {
        let visible = visibleFolders()
        guard !visible.isEmpty else { return }
        let current = selectedFolder.flatMap { s in visible.firstIndex { $0.url == s.url } } ?? -1
        let target = min(max(current + delta, 0), visible.count - 1)
        selectFolder(visible[target])
    }

    /// → key: expand the selected folder. Returns false if it can't (leaf or
    /// already open) so the caller can move focus into the track list instead.
    @discardableResult
    func expandSelectedFolder() -> Bool {
        guard let node = selectedFolder, node.hasSubdirectories != false, !node.isExpanded else { return false }
        tree.toggle(node)
        return true
    }

    /// ← key: collapse the selected folder, else select its parent.
    func collapseOrParent() {
        guard let node = selectedFolder else { return }
        if node.isExpanded { tree.toggle(node); return }
        if let root = tree.root, node.url != root.url, let parent = parentFolder(of: node, in: root) {
            selectFolder(parent)
        }
    }

    private func parentFolder(of target: FileNode, in node: FileNode) -> FileNode? {
        guard let children = node.children else { return nil }
        if children.contains(where: { $0.url == target.url }) { return node }
        for child in children {
            if let found = parentFolder(of: target, in: child) { return found }
        }
        return nil
    }

    func playSelected() {
        if let track = selectedTrack { play(track) }
    }

    // MARK: - Playback

    func play(_ track: Track, in queueTracks: [Track]? = nil) {
        queue = PlayQueue(queueTracks ?? tracks, startingAt: track)
        startCurrentQueueItem()
    }

    /// Start whatever the queue is pointing at, stepping past anything that
    /// won't open. Playlists store plain filesystem paths, so a moved or deleted
    /// track is routine — it should cost you one track, not the rest of the
    /// queue. The loop ends on its own because `advance` walks the index past
    /// the end, where `current` is nil.
    private func startCurrentQueueItem() {
        while let track = queue.current {
            nowPlaying = track
            selectedTrack = track
            if player.play(url: track.url) {
                player.setUpcoming(url: queue.upcoming?.url)
                updateNowPlaying()
                return
            }
            queue.advance()
        }
        nowPlaying = nil
        updateNowPlaying()
    }

    /// The engine hit an unopenable file while advancing on its own — resume the
    /// queue after it.
    private func skipFailedTrack(_ url: URL) {
        guard queue.movePast(url) else {
            nowPlaying = nil
            updateNowPlaying()
            return
        }
        startCurrentQueueItem()
    }

    func playPause() {
        switch player.state {
        case .playing, .paused:
            player.playPauseToggle()
        case .stopped:
            if let track = nowPlaying ?? selectedTrack ?? tracks.first { play(track) }
        }
        updateNowPlaying()
    }

    func playNext() {
        guard !queue.isEmpty else { return }
        guard queue.hasNext else {
            player.stop()
            nowPlaying = nil
            updateNowPlaying()
            return
        }
        queue.advance()
        startCurrentQueueItem()
    }

    func playPrevious() {
        guard !queue.isEmpty else { return }
        if player.position > 3 || queue.isAtStart {
            player.seek(to: 0)
            updateNowPlaying()
            return
        }
        queue.retreat()
        startCurrentQueueItem()
    }

    func seek(to seconds: Double) {
        player.seek(to: seconds)
        updateNowPlaying()
    }

    /// The engine advanced on its own (gapless or format boundary).
    private func engineAdvanced(to url: URL) {
        if queue.move(to: url) { nowPlaying = queue.current }
        player.setUpcoming(url: queue.upcoming?.url)
        updateNowPlaying()
    }

    private func playbackEnded() {
        nowPlaying = nil
        updateNowPlaying()
    }

    // MARK: - Now Playing / remote commands

    private func wireRemoteCommands() {
        nowPlayingService.onToggle = { [weak self] in self?.playPause() }
        nowPlayingService.onPlay = { [weak self] in
            if self?.player.state == .paused { self?.player.resume() } else { self?.playPause() }
            self?.updateNowPlaying()
        }
        nowPlayingService.onPause = { [weak self] in self?.player.pause(); self?.updateNowPlaying() }
        nowPlayingService.onNext = { [weak self] in self?.playNext() }
        nowPlayingService.onPrevious = { [weak self] in self?.playPrevious() }
        nowPlayingService.onSeek = { [weak self] seconds in self?.seek(to: seconds) }
    }

    private func updateNowPlaying() {
        refreshNowPlaying()
        loadNowPlayingArt()
    }

    private func refreshNowPlaying() {
        guard let track = nowPlaying else {
            nowPlayingService.clear()
            return
        }
        nowPlayingService.update(
            title: track.title, artist: track.artist, album: track.album,
            duration: player.duration, elapsed: player.position,
            isPlaying: player.state == .playing, artwork: nowPlayingArt)
    }

    private func loadNowPlayingArt() {
        guard let track = nowPlaying else { nowPlayingArt = nil; nowPlayingArtURL = nil; return }
        guard nowPlayingArtURL != track.url else { return }
        nowPlayingArtURL = track.url
        nowPlayingArt = nil
        let url = track.url
        Task {
            let data = await metadata.artworkData(for: url, maxPixel: 400)
            guard nowPlaying?.url == url, let data, let image = NSImage(data: data) else { return }
            nowPlayingArt = image
            refreshNowPlaying()
        }
    }
}
