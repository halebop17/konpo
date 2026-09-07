import Foundation

/// One disc within an album. Single-folder albums have exactly one disc with a
/// nil label; multi-disc albums have one per CD, labelled "CD 1", "CD 2", …
struct AlbumDisc: Hashable, Sendable {
    /// Header shown above this disc's tracks, e.g. "CD 1". nil = don't show a header.
    let label: String?
    /// The disc's audio files, in on-disk (filename) order.
    let trackURLs: [URL]
}

/// One album in the album-grid view. In Konpo an album is a folder on disk:
/// usually a single folder of tracks, but a multi-disc album is either a parent
/// folder of disc subfolders (CD1/CD2/…) or sibling folders named "Album (CD1)"
/// / "Album (CD2)" — both collapse into one album with multiple discs.
struct Album: Identifiable, Hashable, Sendable {
    /// The album's folder on disk (or the first disc's folder for a multi-disc album).
    let folderURL: URL
    /// Display name — the folder's own name (disc markers stripped when merged).
    let name: String
    /// The album's discs, in order.
    let discs: [AlbumDisc]
    /// Lowercased `name`, precomputed so the grid's live search doesn't lowercase
    /// every album on every keystroke.
    let searchName: String

    init(folderURL: URL, name: String, discs: [AlbumDisc]) {
        self.folderURL = folderURL
        self.name = name
        self.discs = discs
        self.searchName = name.lowercased()
    }

    var id: URL { folderURL }

    /// Every audio file in the album, in disc-then-track order, for playback.
    var trackURLs: [URL] { discs.flatMap(\.trackURLs) }

    /// A track to fall back to for embedded artwork when the folder has no cover.
    var representativeTrackURL: URL? { discs.first?.trackURLs.first }

    /// Whether to show per-disc headers in the tracklist.
    var isMultiDisc: Bool { discs.count > 1 }
}
