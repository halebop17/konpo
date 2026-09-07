import Foundation

/// Builds a throwaway directory tree for the filesystem-walking tests and
/// removes it when the test is done.
///
/// Paths are written as `"Artist/Album/01 Track.flac"`; any component ending in
/// a known audio extension becomes a (zero-byte) file, everything else a
/// directory. Zero-byte files are fine — album discovery only ever looks at
/// names and directory structure, never at file contents.
final class TempTree {
    let root: URL

    init(_ paths: [String]) throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("KonpoTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for path in paths { try make(path) }
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func url(_ path: String) -> URL {
        root.appendingPathComponent(path)
    }

    /// Create a symlink at `path` pointing at `destination` (both tree-relative).
    func link(_ path: String, to destination: String) throws {
        let linkURL = url(path)
        try FileManager.default.createDirectory(
            at: linkURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: url(destination))
    }

    private func make(_ path: String) throws {
        let fm = FileManager.default
        let full = url(path)
        let isFile = Set(["m4a", "mp3", "flac", "aac", "wav", "aiff", "aif", "m4b", "caf",
                          "jpg", "jpeg", "png", "txt", "log", "cue", "nfo"])
            .contains(full.pathExtension.lowercased())
        if isFile {
            try fm.createDirectory(at: full.deletingLastPathComponent(), withIntermediateDirectories: true)
            fm.createFile(atPath: full.path, contents: Data())
        } else {
            try fm.createDirectory(at: full, withIntermediateDirectories: true)
        }
    }
}
