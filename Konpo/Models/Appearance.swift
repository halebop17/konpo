import SwiftUI
import AppKit

/// The user-selectable accent colours and row highlight, and their persistence.
///
/// Split out of AppModel: none of this has anything to do with browsing,
/// playback, or playlists, and it was roughly a sixth of that type — three
/// stored colours, their `didSet` persistence, the `NSColor` round-tripping for
/// the Settings pickers, and the contrast maths.
@MainActor
@Observable
final class Appearance {

    /// Highlights the playing track, selections, and controls.
    var accentHex: UInt32 = 0xF5A623 {
        didSet { Defaults.accentHex = accentHex }
    }

    /// Marks the keyboard-focus edge when the track list is focused (the folder
    /// list uses the primary accent).
    var accent2Hex: UInt32 = 0x4EA1FF {
        didSet { Defaults.accent2Hex = accent2Hex }
    }

    /// Tints the selected (not-playing) row in the track list.
    var highlightHex: UInt32 = 0x9AA0A8 {
        didSet { Defaults.highlightHex = highlightHex }
    }

    init() {
        if let saved = Defaults.accentHex { accentHex = saved }
        if let saved = Defaults.accent2Hex { accent2Hex = saved }
        if let saved = Defaults.highlightHex { highlightHex = saved }
    }

    // MARK: - Derived colours

    var accent: Color { Color(hex: accentHex) }
    var accentTint: Color { accent.opacity(0.10) }
    var accentSelection: Color { accent.opacity(0.16) }

    var accent2: Color { Color(hex: accent2Hex) }

    var highlight: Color { Color(hex: highlightHex) }
    /// The subtle tint actually drawn behind the selected row.
    var highlightSelection: Color { highlight.opacity(0.22) }

    /// Contrasting text colour for on top of the accent (dark on light accents).
    var onAccent: Color {
        Self.isLight(accentHex) ? Color(hex: 0x1B1C1E) : .white
    }

    /// Relative luminance test used to pick readable text over the accent.
    nonisolated static func isLight(_ hex: UInt32) -> Bool {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        return (0.299 * r + 0.587 * g + 0.114 * b) > 0.6
    }

    // MARK: - Two-way bindings for the Settings colour pickers

    var accentColor: Color {
        get { accent }
        set { accentHex = Self.hex(from: newValue, fallback: accentHex) }
    }

    var accent2Color: Color {
        get { accent2 }
        set { accent2Hex = Self.hex(from: newValue, fallback: accent2Hex) }
    }

    var highlightColor: Color {
        get { highlight }
        set { highlightHex = Self.hex(from: newValue, fallback: highlightHex) }
    }

    /// SwiftUI `Color` → packed sRGB hex, keeping the current value if the colour
    /// can't be converted (an unusual colour space from the system picker).
    private static func hex(from color: Color, fallback: UInt32) -> UInt32 {
        guard let ns = NSColor(color).usingColorSpace(.sRGB) else { return fallback }
        let r = UInt32((ns.redComponent * 255).rounded())
        let g = UInt32((ns.greenComponent * 255).rounded())
        let b = UInt32((ns.blueComponent * 255).rounded())
        return (r << 16) | (g << 8) | b
    }
}
