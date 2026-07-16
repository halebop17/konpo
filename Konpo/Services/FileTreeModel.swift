import Foundation
import AppKit

/// Owns the folder tree: the root, lazy directory enumeration, the root picker,
/// and root persistence. Directory I/O runs off the main actor; node mutation
/// happens back on the main actor.
@MainActor
@Observable
final class FileTreeModel {
    private(set) var root: FileNode?

    private let defaultsKey = "rootFolderPath"

    /// Extensions Core Audio can decode. FLAC is supported since macOS 10.13.
    nonisolated static let audioExtensions: Set<String> = [
        "m4a", "mp3", "flac", "aac", "wav", "aiff", "aif", "m4b", "caf",
    ]

    init() {
        if let path = UserDefaults.standard.string(forKey: defaultsKey) {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                let node = FileNode(url: URL(fileURLWithPath: path, isDirectory: true))
                root = node
                Task { await expand(node) }
            }
        }
    }

    // MARK: - Root selection

    func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose your music folder"
        if panel.runModal() == .OK, let url = panel.url {
            setRoot(url)
        }
    }

    func setRoot(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: defaultsKey)
        let node = FileNode(url: url)
        root = node
        Task { await expand(node) }
    }

    // MARK: - Expansion

    func toggle(_ node: FileNode) {
        if node.isExpanded {
            node.isExpanded = false
        } else {
            Task { await expand(node) }
        }
    }

    /// Load a directory's subdirectory children (if needed) and mark it expanded.
    func expand(_ node: FileNode) async {
        guard node.isDirectory else { return }
        if node.children == nil {
            await loadChildren(of: node)
        }
        node.isExpanded = true
    }

    /// Re-read a directory's children from disk (for ⌘R refresh).
    func refresh(_ node: FileNode) async {
        node.children = nil
        await expand(node)
    }

    /// Walk from the root to `url`, expanding each ancestor so the path is
    /// visible, and return the matching node (for restoring the last folder).
    func revealFolder(at url: URL) async -> FileNode? {
        guard let root else { return nil }
        let rootComponents = root.url.standardizedFileURL.pathComponents
        let targetComponents = url.standardizedFileURL.pathComponents
        guard targetComponents.count >= rootComponents.count,
              Array(targetComponents.prefix(rootComponents.count)) == rootComponents else { return nil }
        var node = root
        for component in targetComponents.dropFirst(rootComponents.count) {
            await expand(node)
            guard let child = node.children?.first(where: { $0.name == component }) else { return nil }
            node = child
        }
        return node
    }

    private func loadChildren(of node: FileNode) async {
        node.isLoading = true
        let url = node.url
        let dirs = await Task.detached(priority: .userInitiated) {
            FileTreeModel.subdirectories(of: url)
        }.value
        let nodes = dirs.map { FileNode(url: $0) }
        node.children = nodes
        node.hasSubdirectories = !nodes.isEmpty
        node.isLoading = false
        // Resolve each child's leaf-ness in the background so the tree can show
        // the ♪ icon for album folders without a synchronous deep scan.
        await resolveLeafness(of: nodes)
    }

    private func resolveLeafness(of nodes: [FileNode]) async {
        let urls = nodes.map(\.url)
        let flags = await Task.detached(priority: .utility) {
            urls.map { FileTreeModel.hasSubdirectory($0) }
        }.value
        for (node, hasSub) in zip(nodes, flags) {
            node.hasSubdirectories = hasSub
        }
    }

    // MARK: - Off-main enumeration helpers

    nonisolated static func subdirectories(of url: URL) -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    nonisolated static func hasSubdirectory(_ url: URL) -> Bool {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return false }
        return entries.contains { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    /// All audio files under `url` (recursively), for "add folder to playlist".
    nonisolated static func audioFilesRecursive(in url: URL) -> [Track] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        var files: [URL] = []
        for case let fileURL as URL in enumerator
        where audioExtensions.contains(fileURL.pathExtension.lowercased()) {
            files.append(fileURL)
        }
        return files
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            .map { Track(url: $0) }
    }

    nonisolated static func audioFiles(in url: URL) -> [Track] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries
            .filter { audioExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { Track(url: $0) }
    }

    // MARK: - Album discovery (for the album-grid view)

    /// A single directory listing split into the audio files directly inside it
    /// and its subdirectories — read once per folder so a full walk touches each
    /// directory exactly once.
    private struct DirScan { let audio: [URL]; let subdirs: [URL] }

    /// All albums under `root`, discovered by a directory-only walk (no tag or
    /// artwork decoding). An album is a folder that directly contains audio;
    /// a folder whose audio-bearing children are *all* disc folders (CD1/CD2/…)
    /// collapses into one multi-disc album. Everything else is a branch we
    /// recurse into (e.g. a "Rock" genre folder).
    nonisolated static func albumFolders(under root: URL) -> [Album] {
        var albums: [Album] = []

        func walk(_ dir: URL, _ scan: DirScan) {
            // A folder with its own audio files is one single-disc album.
            if !scan.audio.isEmpty {
                albums.append(Album(folderURL: dir, name: dir.lastPathComponent,
                                    discs: [AlbumDisc(label: nil, trackURLs: sortTracks(scan.audio))]))
                return
            }
            // Otherwise look one level down. Read each child once.
            let childScans = scan.subdirs.map { ($0, scanDirectory($0)) }
            let audioChildren = childScans.filter { !$0.1.audio.isEmpty }

            if !audioChildren.isEmpty,
               audioChildren.allSatisfy({ isDiscFolderName($0.0.lastPathComponent) }) {
                // Multi-disc album via disc SUBfolders (Album/CD1, Album/CD2 …).
                let discs = audioChildren
                    .sorted { $0.0.lastPathComponent.localizedStandardCompare($1.0.lastPathComponent) == .orderedAscending }
                    .map { AlbumDisc(label: normalizeDiscLabel($0.0.lastPathComponent),
                                     trackURLs: sortTracks($0.1.audio)) }
                albums.append(Album(folderURL: dir, name: dir.lastPathComponent, discs: discs))
                return
            }
            // A branch. Emit each audio-bearing child as an album, but first merge
            // sibling disc folders of the same album — e.g. "Album (CD1)" and
            // "Album (CD2)" living side by side (a common multi-disc layout). Then
            // recurse into the non-audio children (deeper branches, or the
            // "Album/CD1" subfolder layout handled at the child level).
            var discGroups: [String: [(url: URL, audio: [URL], label: String)]] = [:]
            var groupOrder: [String] = []
            for (url, sub) in audioChildren {
                if let ds = discSuffix(url.lastPathComponent) {
                    let key = ds.base.lowercased()
                    if discGroups[key] == nil { discGroups[key] = []; groupOrder.append(key) }
                    discGroups[key]?.append((url, sub.audio, ds.label))
                } else {
                    albums.append(Album(folderURL: url, name: url.lastPathComponent,
                                        discs: [AlbumDisc(label: nil, trackURLs: sortTracks(sub.audio))]))
                }
            }
            for key in groupOrder {
                guard let members = discGroups[key] else { continue }
                let ordered = members.sorted {
                    $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
                }
                if ordered.count >= 2 {
                    // Sibling discs → one album named by the shared base.
                    let base = discSuffix(ordered[0].url.lastPathComponent)?.base ?? ordered[0].url.lastPathComponent
                    let discs = ordered.map { AlbumDisc(label: $0.label, trackURLs: sortTracks($0.audio)) }
                    albums.append(Album(folderURL: ordered[0].url, name: base, discs: discs))
                } else {
                    // A lone "(CD1)" with no sibling — keep its original name, one disc.
                    let only = ordered[0]
                    albums.append(Album(folderURL: only.url, name: only.url.lastPathComponent,
                                        discs: [AlbumDisc(label: nil, trackURLs: sortTracks(only.audio))]))
                }
            }
            for (childURL, childScan) in childScans where childScan.audio.isEmpty {
                walk(childURL, childScan)
            }
        }

        walk(root, scanDirectory(root))
        return albums.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private nonisolated static func scanDirectory(_ url: URL) -> DirScan {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return DirScan(audio: [], subdirs: []) }
        var audio: [URL] = []
        var subdirs: [URL] = []
        for entry in entries {
            if (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                subdirs.append(entry)
            } else if audioExtensions.contains(entry.pathExtension.lowercased()) {
                audio.append(entry)
            }
        }
        return DirScan(audio: audio, subdirs: subdirs)
    }

    private nonisolated static func sortTracks(_ urls: [URL]) -> [URL] {
        urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// A disc-subfolder name like "CD1", "CD 1", "CD-01", "Disc 2", "Disk3",
    /// "DVD1", or "CD1 - Subtitle" — case-insensitive, digits after the keyword.
    nonisolated static func isDiscFolderName(_ name: String) -> Bool {
        let lower = name.lowercased()
        for keyword in ["cd", "disc", "disk", "dvd"] where lower.hasPrefix(keyword) {
            let rest = lower.dropFirst(keyword.count).drop { $0 == " " || $0 == "-" || $0 == "_" }
            if let first = rest.first, first.isNumber { return true }
        }
        return false
    }

    /// Matches a *trailing* disc marker on an album folder name: "(CD1)",
    /// "(Disc 2)", " CD1", " - Disc 1", "[Disk 2]", "Disc 1 of 2". Anchored to the
    /// end and limited to cd/disc/disk/dvd + a number, so "…, Vol. 2", a year, or
    /// "No. 2" are never treated as discs. Group 1 = album base, group 2 = marker.
    private nonisolated static let discSuffixRegex = try! NSRegularExpression(
        pattern: "^(.*?)[\\s._\\-]*[\\(\\[]?\\s*((?:cd|dis[ck]|dvd)\\s*\\.?\\s*\\d+(?:\\s*of\\s*\\d+)?)\\s*[\\)\\]]?\\s*$",
        options: [.caseInsensitive])

    /// If a folder name carries a trailing disc marker, returns its album base and
    /// a normalized disc label. "Bob Marley - Legend (CD1)" → ("Bob Marley - Legend",
    /// "CD 1"). "Best of, Vol. 2" or a bare "CD1" (a disc *subfolder*) → nil.
    nonisolated static func discSuffix(_ name: String) -> (base: String, label: String)? {
        let range = NSRange(name.startIndex..., in: name)
        guard let match = discSuffixRegex.firstMatch(in: name, options: [], range: range),
              let baseRange = Range(match.range(at: 1), in: name),
              let markerRange = Range(match.range(at: 2), in: name) else {
            return nil
        }
        let base = String(name[baseRange])
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t-_.(["))
        guard !base.isEmpty else { return nil }
        return (base, normalizeDiscLabel(String(name[markerRange])))
    }

    /// A clean disc header from a raw marker or disc-folder name:
    /// "cd1" / "CD 1" → "CD 1", "disc2" → "Disc 2", "dvd1" → "DVD 1".
    nonisolated static func normalizeDiscLabel(_ raw: String) -> String {
        let lower = raw.lowercased()
        let digits = String(lower.drop { !$0.isNumber }.prefix { $0.isNumber })
        let keyword: String
        if lower.hasPrefix("cd") { keyword = "CD" }
        else if lower.hasPrefix("dvd") { keyword = "DVD" }
        else if lower.hasPrefix("disk") { keyword = "Disk" }
        else { keyword = "Disc" }
        return digits.isEmpty ? keyword : "\(keyword) \(digits)"
    }
}
