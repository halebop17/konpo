import Foundation

/// Counted nouns, phrased so the string catalog can carry real plural rules.
///
/// These were built as `"\(n) album" + (n == 1 ? "" : "s")`, which bakes English
/// pluralisation into the code — many languages need more than a trailing "s",
/// and several have more than two plural categories. Going through
/// `String(localized:)` lets the catalog supply per-language variations instead.
enum Counts {
    static func albums(_ count: Int) -> String {
        String(localized: "\(count) albums", comment: "Album count in the album grid toolbar")
    }

    static func tracks(_ count: Int) -> String {
        String(localized: "\(count) tracks", comment: "Track count, spoken by VoiceOver")
    }
}
