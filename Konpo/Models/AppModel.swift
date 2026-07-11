import Foundation
import AppKit
import SwiftUI

/// Composition root. Owns the folder tree, player, metadata, and Now Playing
/// bridge, plus the current folder/track selection and the play queue.
@MainActor
@Observable
final class AppModel {
    let tree = FileTreeModel()
    let player = PlayerEngine()
    let metadata = MetadataService()
    let playlists = PlaylistStore()
    @ObservationIgnored let nowPlayingService = NowPlayingService()

    enum SidebarMode { case folders, playlists }

    var selectedFolder: FileNode?
    var tracks: [Track] = []
    var selectedTrack: Track?
    var nowPlaying: Track?
    /// Transient error banner text (auto-clears).
    var errorMessage: String?

    // Sidebar / playlists
    var sidebarMode: SidebarMode = .folders {
        didSet { UserDefaults.standard.set(sidebarMode == .playlists ? "playlists" : "folders", forKey: "sidebarMode") }
    }
    var selectedPlaylist: Playlist?
    var showNewPlaylistPrompt = false
    var newPlaylistName = ""

    /// Track whose album art the full-size art window should display.
    var artworkFullURL: URL?

    /// Optional user folder of visualizer presets (.milk or .json). nil = built-in.
    var visualizerPresetFolder: String? {
        didSet {
            if let v = visualizerPresetFolder { UserDefaults.standard.set(v, forKey: "vizPresetFolder") }
            else { UserDefaults.standard.removeObject(forKey: "vizPresetFolder") }
        }
    }

    private enum PendingPlaylistAdd { case none, track(URL), folder(URL) }
    private var pendingAdd: PendingPlaylistAdd = .none

    // MARK: Appearance (user-selectable accent color)

    var accentHex: UInt32 = 0xF5A623 {
        didSet { UserDefaults.standard.set(Int(accentHex), forKey: "accentHex") }
    }
    var accent: Color { Color(hex: accentHex) }
    var accentTint: Color { accent.opacity(0.10) }
    var accentSelection: Color { accent.opacity(0.16) }
    /// Contrasting text color for on top of the accent (dark on light accents).
    var onAccent: Color {
        let r = Double((accentHex >> 16) & 0xFF) / 255
        let g = Double((accentHex >> 8) & 0xFF) / 255
        let b = Double(accentHex & 0xFF) / 255
        return (0.299 * r + 0.587 * g + 0.114 * b) > 0.6 ? Color(hex: 0x1B1C1E) : .white
    }
    /// Two-way `Color` binding for the Settings color picker.
    var accentColor: Color {
        get { accent }
        set {
            let ns = NSColor(newValue).usingColorSpace(.sRGB) ?? NSColor(srgbRed: 0.96, green: 0.65, blue: 0.14, alpha: 1)
            let r = UInt32((ns.redComponent * 255).rounded())
            let g = UInt32((ns.greenComponent * 255).rounded())
            let b = UInt32((ns.blueComponent * 255).rounded())
            accentHex = (r << 16) | (g << 8) | b
        }
    }

    /// Second accent — used to tint the keyboard-focus marker on the track list
    /// (the folder list uses the primary accent).
    var accent2Hex: UInt32 = 0x4EA1FF {
        didSet { UserDefaults.standard.set(Int(accent2Hex), forKey: "accent2Hex") }
    }
    var accent2: Color { Color(hex: accent2Hex) }
    var accent2Color: Color {
        get { accent2 }
        set {
            let ns = NSColor(newValue).usingColorSpace(.sRGB) ?? NSColor(srgbRed: 0.31, green: 0.63, blue: 1, alpha: 1)
            let r = UInt32((ns.redComponent * 255).rounded())
            let g = UInt32((ns.greenComponent * 255).rounded())
            let b = UInt32((ns.blueComponent * 255).rounded())
            accent2Hex = (r << 16) | (g << 8) | b
        }
    }

    /// Highlight color for the selected (not-playing) row in the track list.
    var highlightHex: UInt32 = 0x9AA0A8 {
        didSet { UserDefaults.standard.set(Int(highlightHex), forKey: "highlightHex") }
    }
    var highlight: Color { Color(hex: highlightHex) }
    /// The subtle tint actually drawn behind the selected row.
    var highlightSelection: Color { highlight.opacity(0.22) }
    var highlightColor: Color {
        get { highlight }
        set {
            let ns = NSColor(newValue).usingColorSpace(.sRGB) ?? NSColor(srgbRed: 0.6, green: 0.63, blue: 0.66, alpha: 1)
            let r = UInt32((ns.redComponent * 255).rounded())
            let g = UInt32((ns.greenComponent * 255).rounded())
            let b = UInt32((ns.blueComponent * 255).rounded())
            highlightHex = (r << 16) | (g << 8) | b
        }
    }

    private var playQueue: [Track] = []
    private var queueIndex = 0

    private var loadTracksTask: Task<Void, Never>?
    private var errorClearTask: Task<Void, Never>?
    private var nowPlayingArt: NSImage?
    private var nowPlayingArtURL: URL?

    private let lastFolderKey = "lastFolderPath"

    init() {
        if let saved = UserDefaults.standard.object(forKey: "accentHex") as? Int {
            accentHex = UInt32(saved)
        }
        if let saved = UserDefaults.standard.object(forKey: "accent2Hex") as? Int {
            accent2Hex = UInt32(saved)
        }
        if let saved = UserDefaults.standard.object(forKey: "highlightHex") as? Int {
            highlightHex = UInt32(saved)
        }
        visualizerPresetFolder = UserDefaults.standard.string(forKey: "vizPresetFolder")
        player.onTrackChanged = { [weak self] url in self?.engineAdvanced(to: url) }
        player.onPlaybackEnded = { [weak self] in self?.playbackEnded() }
        player.onError = { [weak self] message in self?.showError(message) }
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
        UserDefaults.standard.set(node.url.path, forKey: lastFolderKey)
        loadTracks(from: node.url)
    }

    /// On launch, restore the sidebar mode plus the last folder/playlist.
    private func restoreSession() {
        guard tree.root != nil else { return }
        let playlistsMode = UserDefaults.standard.string(forKey: "sidebarMode") == "playlists"
        Task {
            // Resolve the last folder node so switching back to Folders works.
            let lastPath = UserDefaults.standard.string(forKey: lastFolderKey)
            let node: FileNode?
            if let lastPath {
                node = await tree.revealFolder(at: URL(fileURLWithPath: lastPath, isDirectory: true)) ?? tree.root
            } else {
                node = tree.root
            }
            selectedFolder = node

            if playlistsMode {
                sidebarMode = .playlists
                if let idString = UserDefaults.standard.string(forKey: "lastPlaylistID"),
                   let id = UUID(uuidString: idString),
                   let playlist = playlists.playlists.first(where: { $0.id == id }) {
                    selectPlaylist(playlist)
                }
            } else if let node {
                selectFolder(node)
            }
        }
    }

    /// ⌘R: re-read the current folder's subfolders and tracks from disk.
    func refresh() {
        guard let folder = selectedFolder else { return }
        Task {
            await metadata.clearCache()
            await tree.refresh(folder)
            loadTracks(from: folder.url)
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
        startTrackLoad {
            await Task.detached(priority: .userInitiated) { FileTreeModel.audioFiles(in: url) }.value
        }
    }

    private func loadTracks(urls: [URL]) {
        startTrackLoad { urls.map { Track(url: $0) } }
    }

    private func startTrackLoad(_ produce: @escaping @Sendable () async -> [Track]) {
        loadTracksTask?.cancel()
        loadTracksTask = Task {
            let files = await produce()
            if Task.isCancelled { return }
            tracks = files
            if selectedTrack == nil { selectedTrack = files.first }
            await loadMetadata(for: files)
        }
    }

    // MARK: - Playlists

    func setSidebarMode(_ mode: SidebarMode) {
        sidebarMode = mode
        selectedTrack = nil
        switch mode {
        case .folders:
            if let folder = selectedFolder { loadTracks(from: folder.url) } else { tracks = [] }
        case .playlists:
            if let playlist = selectedPlaylist { selectPlaylist(playlist) } else { tracks = [] }
        }
    }

    func selectPlaylist(_ playlist: Playlist) {
        selectedPlaylist = playlist
        selectedTrack = nil
        UserDefaults.standard.set(playlist.id.uuidString, forKey: "lastPlaylistID")
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
        if sidebarMode == .playlists, selectedPlaylist?.id == id,
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
            sidebarMode = .playlists
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

    func play(_ track: Track, in queue: [Track]? = nil) {
        playQueue = queue ?? tracks
        queueIndex = playQueue.firstIndex { $0.url == track.url } ?? 0
        nowPlaying = track
        selectedTrack = track
        player.play(url: track.url)
        player.setUpcoming(url: upcomingURL())
        updateNowPlaying()
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
        guard !playQueue.isEmpty else { return }
        let next = queueIndex + 1
        guard next < playQueue.count else {
            player.stop()
            nowPlaying = nil
            updateNowPlaying()
            return
        }
        play(playQueue[next], in: playQueue)
    }

    func playPrevious() {
        guard !playQueue.isEmpty else { return }
        if player.position > 3 || queueIndex == 0 {
            player.seek(to: 0)
            updateNowPlaying()
            return
        }
        play(playQueue[queueIndex - 1], in: playQueue)
    }

    func seek(to seconds: Double) {
        player.seek(to: seconds)
        updateNowPlaying()
    }

    /// The engine advanced on its own (gapless or format boundary).
    private func engineAdvanced(to url: URL) {
        if let index = playQueue.firstIndex(where: { $0.url == url }) {
            queueIndex = index
            nowPlaying = playQueue[index]
        }
        player.setUpcoming(url: upcomingURL())
        updateNowPlaying()
    }

    private func playbackEnded() {
        nowPlaying = nil
        updateNowPlaying()
    }

    private func upcomingURL() -> URL? {
        let next = queueIndex + 1
        return next < playQueue.count ? playQueue[next].url : nil
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
