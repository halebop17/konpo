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
}
