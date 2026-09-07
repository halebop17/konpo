import Testing
import SwiftUI
@testable import Konpo

/// The text-size scale is clamped rather than followed all the way, because the
/// dense five-column layout stops fitting well before the system setting stops
/// growing. These pin the bounds so the cap can't drift without someone
/// re-checking the layout at that size.
struct ScaledThemeTests {

    @Test("The design's own sizes are the floor — never scale below 1")
    func floor() {
        #expect(ScaledThemeProvider.clamp(0.5) == 1)
        #expect(ScaledThemeProvider.clamp(0.99) == 1)
        #expect(ScaledThemeProvider.clamp(1) == 1)
    }

    @Test("Scaling is capped where the layout was measured to still hold")
    func ceiling() {
        #expect(ScaledThemeProvider.clamp(1.4) == ScaledThemeProvider.maxScale)
        #expect(ScaledThemeProvider.clamp(3) == ScaledThemeProvider.maxScale)
        #expect(ScaledThemeProvider.maxScale == 1.15)
    }

    @Test("Values inside the range pass through")
    func passthrough() {
        #expect(ScaledThemeProvider.clamp(1.1) == 1.1)
    }

    /// A non-finite value from the environment must not reach a frame width.
    @Test("Non-finite input falls back to 1")
    func nonFinite() {
        #expect(ScaledThemeProvider.clamp(.nan) == 1)
        #expect(ScaledThemeProvider.clamp(.infinity) == 1)
    }

    @Test("Metrics and fonts scale together")
    func metricsScale() {
        let theme = ScaledTheme(scale: 1.1)
        #expect(theme.rowHeight == Theme.rowHeight * 1.1)
        #expect(theme.colNumWidth == Theme.colNumWidth * 1.1)
        #expect(theme.colTimeWidth == Theme.colTimeWidth * 1.1)
        // Approximate: 100 * 1.1 is 110.00000000000001 in binary floating point.
        #expect(abs(theme.metric(100) - 110) < 0.0001)
    }

    @Test("At scale 1 nothing moves")
    func identity() {
        let theme = ScaledTheme(scale: 1)
        #expect(theme.rowHeight == Theme.rowHeight)
        #expect(theme.metric(42) == 42)
        #expect(theme.body == Theme.fontSize)
    }
}
