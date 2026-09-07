import Testing
@testable import Konpo

/// Pins the palette's readability. The two secondary greys were previously
/// #71737A (3.6:1) and #5A5C62 (2.55:1) against the window background — the
/// dimmer of the two well under any WCAG threshold, while being used for track
/// numbers, column headings and disc headers.
struct ContrastTests {

    @Test("The luminance maths matches known WCAG values")
    func luminanceReference() {
        #expect(abs(Theme.relativeLuminance(0xFFFFFF) - 1.0) < 0.0001)
        #expect(abs(Theme.relativeLuminance(0x000000) - 0.0) < 0.0001)
        // Black on white is the canonical 21:1.
        #expect(abs(Theme.contrastRatio(0x000000, 0xFFFFFF) - 21.0) < 0.01)
        // Ratio is symmetric.
        #expect(Theme.contrastRatio(0x123456, 0xABCDEF) == Theme.contrastRatio(0xABCDEF, 0x123456))
    }

    @Test("Primary text clears AA comfortably")
    func primaryText() {
        #expect(Theme.contrastRatio(Theme.Hex.text, Theme.Hex.window) >= 4.5)
    }

    /// Artist, album and duration text: real content, so the body-text ratio.
    @Test("Secondary text meets AA for body text")
    func mutedText() {
        #expect(Theme.contrastRatio(Theme.Hex.muted, Theme.Hex.window) >= 4.5)
    }

    /// Column headings, track numbers, disc headers: deliberately quiet, held to
    /// the 3:1 large/secondary threshold rather than 4.5:1 so the dense table
    /// keeps its look.
    @Test("Tertiary labels meet the 3:1 threshold")
    func dimLabels() {
        #expect(Theme.contrastRatio(Theme.Hex.dim, Theme.Hex.window) >= 3.0)
    }

    @Test("Secondary text is readable on every surface, not just the window")
    func acrossSurfaces() {
        for background in [Theme.Hex.window, Theme.Hex.sidebar, Theme.Hex.panel, Theme.Hex.titlebar] {
            #expect(Theme.contrastRatio(Theme.Hex.muted, background) >= 4.5)
            #expect(Theme.contrastRatio(Theme.Hex.dim, background) >= 3.0)
            #expect(Theme.contrastRatio(Theme.Hex.text, background) >= 4.5)
        }
    }

    /// The accent is user-selectable, so what matters is that the text drawn on
    /// top of it flips with the accent's lightness.
    @Test("onAccent flips to keep text legible over light and dark accents")
    func onAccentFlips() {
        #expect(Appearance.isLight(0xF5A623))   // default amber → dark text
        #expect(Appearance.isLight(0xE8E9EC))   // off-white preset
        #expect(!Appearance.isLight(0x0A84FF))  // blue → white text
        #expect(!Appearance.isLight(0x2F9E63))  // green
        #expect(!Appearance.isLight(0x000000))
        #expect(Appearance.isLight(0xFFFFFF))
    }
}
