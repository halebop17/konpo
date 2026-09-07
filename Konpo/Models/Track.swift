import Foundation

/// One audio file in the track list. Starts as filename-only; the metadata
/// service fills the tag/format fields asynchronously.
struct Track: Identifiable, Hashable, Sendable {
    let url: URL
    var title: String
    var artist: String = ""
    var album: String = ""
    var trackNumber: Int?
    var durationSeconds: Double?
    var year: String?
    var codec: String?
    var sampleRate: Double?
    var bitDepth: Int?
    var channels: Int?
    var metadataLoaded = false

    var id: URL { url }

    /// File extension uppercased (e.g. "M4A") — a fallback format hint.
    var formatHint: String { url.pathExtension.uppercased() }

    /// Formatted duration ("m:ss", or "h:mm:ss" past the hour), empty until
    /// metadata loads so the track list can show its own placeholder.
    var durationText: String {
        guard let secs = durationSeconds, secs.isFinite, secs >= 0 else { return "" }
        return TimeFormat.string(secs)
    }

    init(url: URL) {
        self.url = url
        self.title = url.deletingPathExtension().lastPathComponent
    }

    mutating func apply(_ m: TrackMetadata) {
        if let t = m.title, !t.isEmpty { title = t }
        if let a = m.artist { artist = a }
        if let al = m.album { album = al }
        trackNumber = m.trackNumber
        durationSeconds = m.durationSeconds
        year = m.year
        codec = m.codec
        sampleRate = m.sampleRate
        bitDepth = m.bitDepth
        channels = m.channels
        metadataLoaded = true
    }
}
