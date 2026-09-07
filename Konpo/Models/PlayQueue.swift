import Foundation

/// The tracks playback is moving through, and the position within them.
///
/// A plain value type with no knowledge of the audio engine, so the stepping
/// rules — what is next, what happens at the ends, how a re-sort keeps the
/// playing track playing, how a file that won't open is stepped over — can be
/// exercised directly in tests. That logic previously lived as a bare array and
/// index inside AppModel, where it was untestable and where an off-by-one had
/// real consequences.
///
/// `index` is allowed to run one past the end; `current` is nil there, which is
/// what lets the skip loop terminate naturally.
struct PlayQueue {
    private(set) var tracks: [Track]
    private(set) var index: Int

    init(_ tracks: [Track] = [], startingAt track: Track? = nil) {
        self.tracks = tracks
        self.index = track.flatMap { wanted in
            tracks.firstIndex { $0.url == wanted.url }
        } ?? 0
    }

    var isEmpty: Bool { tracks.isEmpty }
    var isAtStart: Bool { index == 0 }
    var hasNext: Bool { index + 1 < tracks.count }

    var current: Track? { tracks.indices.contains(index) ? tracks[index] : nil }
    var upcoming: Track? { tracks.indices.contains(index + 1) ? tracks[index + 1] : nil }

    /// Step forward. Deliberately allowed to land past the end so callers can
    /// loop on `current` instead of counting.
    mutating func advance() {
        index += 1
    }

    mutating func retreat() {
        if index > 0 { index -= 1 }
    }

    /// Move onto `url`, if it is in the queue.
    @discardableResult
    mutating func move(to url: URL) -> Bool {
        guard let found = tracks.firstIndex(where: { $0.url == url }) else { return false }
        index = found
        return true
    }

    /// Move to just after `url` — for stepping over a file that wouldn't open.
    @discardableResult
    mutating func movePast(_ url: URL) -> Bool {
        guard let found = tracks.firstIndex(where: { $0.url == url }) else { return false }
        index = found + 1
        return true
    }

    /// Replace the tracks with the same set in a new order, keeping whatever is
    /// current still current. Does nothing and returns false for a different set,
    /// so re-sorting a folder can't disturb a queue that came from elsewhere.
    @discardableResult
    mutating func reorder(to newTracks: [Track]) -> Bool {
        guard Set(newTracks.map(\.url)) == Set(tracks.map(\.url)) else { return false }
        let currentURL = current?.url
        tracks = newTracks
        if let currentURL, let found = newTracks.firstIndex(where: { $0.url == currentURL }) {
            index = found
        }
        return true
    }
}
