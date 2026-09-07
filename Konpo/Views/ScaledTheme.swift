import SwiftUI

/// Konpo's type and row metrics, scaled by the system text-size setting
/// (System Settings → Accessibility → Display → Text size, which macOS 14
/// exposes app-wide).
///
/// SwiftUI's `.system(size:)` fonts are fixed by design — they do not respond to
/// that setting at all — so a UI built from explicit point sizes, as this one
/// is, has to do the scaling itself. Measured once at the root and passed down
/// through the environment rather than each view carrying its own
/// `@ScaledMetric`.
struct ScaledTheme {
    let scale: CGFloat

    func font(_ points: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: points * scale, weight: weight)
    }

    /// Track numbers, durations, technical metadata.
    func mono(_ points: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: points * scale, weight: weight, design: .monospaced)
    }

    /// A fixed metric (row height, column width, padding) scaled to match.
    func metric(_ points: CGFloat) -> CGFloat { points * scale }

    var rowHeight: CGFloat { Theme.rowHeight * scale }
    var body: CGFloat { Theme.fontSize * scale }
    var colNumWidth: CGFloat { Theme.colNumWidth * scale }
    var colTimeWidth: CGFloat { Theme.colTimeWidth * scale }
}

private struct ScaledThemeKey: EnvironmentKey {
    static let defaultValue = ScaledTheme(scale: 1)
}

extension EnvironmentValues {
    var scaled: ScaledTheme {
        get { self[ScaledThemeKey.self] }
        set { self[ScaledThemeKey.self] = newValue }
    }
}

/// Measures the system text scale once and publishes it to the hierarchy.
/// Apply at the root of each window scene.
struct ScaledThemeProvider: ViewModifier {
    /// `@ScaledMetric` is the only thing that actually reads the system setting;
    /// scaling a round number makes the ratio easy to recover.
    @ScaledMetric(relativeTo: .body) private var probe: CGFloat = 100

    func body(content: Content) -> some View {
        content.environment(\.scaled, ScaledTheme(scale: Self.clamp(probe / 100)))
    }

    /// The design's own sizes are the floor, and 1.15 is the ceiling — measured,
    /// not guessed. Screenshots at each step: 1.15 holds everything; by 1.25 the
    /// sidebar header clips, the ARTIST/ALBUM column headings wrap mid-word, the
    /// Album column collapses to an ellipsis and the art panel runs off the right
    /// edge taking its metadata with it; 1.4 is unusable.
    ///
    /// Going further needs the layout to become responsive first — columns that
    /// can drop, a sidebar that sizes to its content, an art panel that can
    /// collapse — which is a design change, not a scaling one. Until then,
    /// stopping early is better than clipping.
    static let maxScale: CGFloat = 1.15

    static func clamp(_ raw: CGFloat) -> CGFloat {
        guard raw.isFinite else { return 1 }
        return min(max(raw, 1), maxScale)
    }
}

extension View {
    func konpoTextScaling() -> some View { modifier(ScaledThemeProvider()) }
}
