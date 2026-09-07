import Testing
import Foundation
@testable import Konpo

struct TimeFormatTests {

    @Test("Sub-hour durations format as m:ss", arguments: [
        (0.0, "0:00"),
        (1.0, "0:01"),
        (9.0, "0:09"),
        (59.0, "0:59"),
        (60.0, "1:00"),
        (61.0, "1:01"),
        (599.0, "9:59"),
        (600.0, "10:00"),
        (3599.0, "59:59"),
    ])
    func minutesAndSeconds(seconds: Double, expected: String) {
        #expect(TimeFormat.string(seconds) == expected)
    }

    /// The reason this helper exists: m4b is a supported extension, so an
    /// audiobook used to render as "125:33" instead of "2:05:33".
    @Test("Hour-plus durations gain an hours component", arguments: [
        (3600.0, "1:00:00"),
        (3661.0, "1:01:01"),
        (7533.0, "2:05:33"),
        (36000.0, "10:00:00"),
    ])
    func hours(seconds: Double, expected: String) {
        #expect(TimeFormat.string(seconds) == expected)
    }

    @Test("Non-finite and negative values fall back to 0:00", arguments: [
        Double.nan, .infinity, -.infinity, -1, -0.4,
    ])
    func invalidValues(seconds: Double) {
        #expect(TimeFormat.string(seconds) == "0:00")
    }

    @Test("Seconds are rounded, not truncated")
    func rounding() {
        #expect(TimeFormat.string(59.6) == "1:00")
        #expect(TimeFormat.string(59.4) == "0:59")
    }
}

struct TrackTests {

    @Test("A new track falls back to its filename and file extension")
    func defaults() {
        let track = Track(url: URL(fileURLWithPath: "/Music/Album/03 Some Song.flac"))
        #expect(track.title == "03 Some Song")
        #expect(track.formatHint == "FLAC")
        #expect(track.metadataLoaded == false)
        #expect(track.durationText == "")
    }

    @Test("durationText stays empty until metadata arrives, then formats")
    func durationText() {
        var track = Track(url: URL(fileURLWithPath: "/Music/a.mp3"))
        #expect(track.durationText == "")
        track.durationSeconds = 7533
        #expect(track.durationText == "2:05:33")
        track.durationSeconds = .nan
        #expect(track.durationText == "")
    }

    @Test("Applying metadata does not blank an existing title with an empty tag")
    func emptyTitleTagIgnored() {
        var track = Track(url: URL(fileURLWithPath: "/Music/03 Fallback Name.mp3"))
        var meta = TrackMetadata()
        meta.title = ""
        meta.artist = "Someone"
        track.apply(meta)
        #expect(track.title == "03 Fallback Name")
        #expect(track.artist == "Someone")
        #expect(track.metadataLoaded)
    }
}

/// The seek/volume bar's drag maths. `fraction(of:in:)` is the guard against a
/// zero-width bar producing NaN and trapping in `PlayerEngine.seek(to:)`.
struct DraggableBarFractionTests {

    @Test("Positions map to 0…1 across the bar")
    func normalPositions() {
        #expect(DraggableBar.fraction(of: 0, in: 200) == 0)
        #expect(DraggableBar.fraction(of: 100, in: 200) == 0.5)
        #expect(DraggableBar.fraction(of: 200, in: 200) == 1)
    }

    @Test("Drags past either end clamp instead of overshooting")
    func clamping() {
        #expect(DraggableBar.fraction(of: -50, in: 200) == 0)
        #expect(DraggableBar.fraction(of: 500, in: 200) == 1)
    }

    @Test("A zero-width bar yields nil rather than NaN")
    func zeroWidth() {
        #expect(DraggableBar.fraction(of: 10, in: 0) == nil)
        #expect(DraggableBar.fraction(of: 0, in: 0) == nil)
        #expect(DraggableBar.fraction(of: 10, in: -5) == nil)
    }

    @Test("A non-finite drag position yields nil")
    func nonFinitePosition() {
        #expect(DraggableBar.fraction(of: .nan, in: 200) == nil)
        #expect(DraggableBar.fraction(of: .infinity, in: 200) == nil)
    }
}
