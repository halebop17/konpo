import Foundation

/// Playback time formatting, shared by the track list, the art panel, and the
/// transport bar so they can't drift apart.
enum TimeFormat {
    /// "m:ss", widening to "h:mm:ss" past the hour. Without the hour component a
    /// two-hour file reads as "125:33" — and `m4b` is a supported extension, so
    /// audiobooks hit this routinely.
    static func string(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}
