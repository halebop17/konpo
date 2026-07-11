import Foundation

/// A directory node in the folder tree. Reference type so lazy child loading can
/// mutate a node in place and let SwiftUI observe it via @Observable.
@Observable
final class FileNode: Identifiable {
    let url: URL
    let name: String
    let isDirectory: Bool

    /// Subdirectory children shown in the tree. `nil` = not yet loaded.
    var children: [FileNode]?
    var isExpanded = false
    var isLoading = false

    /// Whether this directory contains subdirectories — drives the disclosure
    /// triangle vs the ♪ "leaf album folder" icon. `nil` = not yet determined.
    var hasSubdirectories: Bool?

    var id: URL { url }

    init(url: URL, isDirectory: Bool = true, hasSubdirectories: Bool? = nil) {
        self.url = url
        self.isDirectory = isDirectory
        self.name = url.lastPathComponent
        self.hasSubdirectories = hasSubdirectories
    }
}
