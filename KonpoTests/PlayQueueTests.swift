import Testing
import Foundation
@testable import Konpo

/// The queue stepping rules. These used to be a bare array and index inside
/// AppModel, where a file that wouldn't open ended playback entirely.
struct PlayQueueTests {

    private func tracks(_ names: String...) -> [Track] {
        names.map { Track(url: URL(fileURLWithPath: "/Music/\($0).flac")) }
    }

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/Music/\(name).flac")
    }

    @Test("An empty queue has nothing current or upcoming")
    func empty() {
        let queue = PlayQueue()
        #expect(queue.isEmpty)
        #expect(queue.current == nil)
        #expect(queue.upcoming == nil)
        #expect(!queue.hasNext)
    }

    @Test("Starts at the requested track, not the beginning")
    func startsAtRequestedTrack() {
        let queue = PlayQueue(tracks("a", "b", "c"), startingAt: tracks("b")[0])
        #expect(queue.current?.url == url("b"))
        #expect(queue.upcoming?.url == url("c"))
        #expect(!queue.isAtStart)
    }

    @Test("A track that isn't in the queue starts it from the beginning")
    func unknownStartTrack() {
        let queue = PlayQueue(tracks("a", "b"), startingAt: tracks("zzz")[0])
        #expect(queue.current?.url == url("a"))
        #expect(queue.isAtStart)
    }

    @Test("Advancing walks to the end and then past it")
    func advanceToEnd() {
        var queue = PlayQueue(tracks("a", "b"), startingAt: tracks("a")[0])
        #expect(queue.hasNext)
        queue.advance()
        #expect(queue.current?.url == url("b"))
        #expect(!queue.hasNext)
        #expect(queue.upcoming == nil)
        // Deliberately allowed past the end, which is what lets the skip loop
        // in AppModel terminate on `current` being nil.
        queue.advance()
        #expect(queue.current == nil)
    }

    @Test("Retreating stops at the start rather than going negative")
    func retreatClamps() {
        var queue = PlayQueue(tracks("a", "b"), startingAt: tracks("b")[0])
        queue.retreat()
        #expect(queue.current?.url == url("a"))
        queue.retreat()
        #expect(queue.current?.url == url("a"))
        #expect(queue.isAtStart)
    }

    @Test("Moving to a known track succeeds, unknown fails and changes nothing")
    func moveTo() {
        var queue = PlayQueue(tracks("a", "b", "c"), startingAt: tracks("a")[0])
        let movedToC = queue.move(to: url("c"))
        #expect(movedToC)
        #expect(queue.current?.url == url("c"))
        let movedToUnknown = queue.move(to: url("nope"))
        #expect(!movedToUnknown)
        #expect(queue.current?.url == url("c"))
    }

    /// The skip path: a file that won't open should cost one track, not the rest.
    @Test("movePast lands on the following track")
    func movePast() {
        var queue = PlayQueue(tracks("a", "b", "c"), startingAt: tracks("a")[0])
        let skipped = queue.movePast(url("a"))
        #expect(skipped)
        #expect(queue.current?.url == url("b"))
    }

    @Test("movePast the last track leaves the queue exhausted, not wrapped")
    func movePastLast() {
        var queue = PlayQueue(tracks("a", "b"), startingAt: tracks("b")[0])
        let skippedLast = queue.movePast(url("b"))
        #expect(skippedLast)
        #expect(queue.current == nil)
    }

    @Test("movePast an unknown track reports failure")
    func movePastUnknown() {
        var queue = PlayQueue(tracks("a", "b"), startingAt: tracks("a")[0])
        let skippedUnknown = queue.movePast(url("nope"))
        #expect(!skippedUnknown)
        #expect(queue.current?.url == url("a"))
    }

    // MARK: - Reordering

    @Test("Reordering the same set keeps the playing track current")
    func reorderKeepsCurrent() {
        var queue = PlayQueue(tracks("a", "b", "c"), startingAt: tracks("c")[0])
        let reordered = queue.reorder(to: tracks("c", "a", "b"))
        #expect(reordered)
        #expect(queue.current?.url == url("c"))
        #expect(queue.index == 0)
        #expect(queue.upcoming?.url == url("a"))
    }

    /// Why the set check exists: re-sorting a browsed folder must not reach into
    /// playback that was started from a playlist or another album.
    @Test("Reordering a different set is refused and changes nothing")
    func reorderDifferentSetRefused() {
        var queue = PlayQueue(tracks("a", "b"), startingAt: tracks("a")[0])
        let reorderedOther = queue.reorder(to: tracks("x", "y"))
        #expect(!reorderedOther)
        #expect(queue.tracks.map(\.url) == [url("a"), url("b")])
        #expect(queue.current?.url == url("a"))
    }

    @Test("Reordering a subset or superset is refused")
    func reorderPartialRefused() {
        var queue = PlayQueue(tracks("a", "b", "c"), startingAt: tracks("a")[0])
        let reorderedSubset = queue.reorder(to: tracks("a", "b"))
        let reorderedSuperset = queue.reorder(to: tracks("a", "b", "c", "d"))
        #expect(!reorderedSubset)
        #expect(!reorderedSuperset)
        #expect(queue.tracks.count == 3)
    }
}
