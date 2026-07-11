import SwiftUI

/// Design tokens from the Konpo mockup (docs/plan.md, Konpo (standalone).html).
enum Theme {
    // Colors — fixed dark charcoal base, amber accent
    static let accent = Color(hex: 0xF5A623)
    static let window = Color(hex: 0x1B1C1E)
    static let titlebar = Color(hex: 0x212224)
    static let sidebar = Color(hex: 0x1E1F22)
    static let panel = Color(hex: 0x1D1E21)
    static let text = Color(hex: 0xD8D9DD)
    static let muted = Color(hex: 0x71737A)
    static let dim = Color(hex: 0x5A5C62)
    static let separator = Color.white.opacity(0.06)
    static let sliderTrack = Color.white.opacity(0.13)
    /// Text color used on top of the accent (accent is light amber → dark text)
    static let onAccent = Color(hex: 0x1B1C1E)
    /// Tinted background for the playing/selected row
    static let accentTint = accent.opacity(0.10)
    static let accentSelection = accent.opacity(0.16)

    // Metrics ("dense" density from the mockup)
    static let rowHeight: CGFloat = 22
    static let fontSize: CGFloat = 12
    static let titlebarHeight: CGFloat = 36
    static let sidebarWidth: CGFloat = 186
    static let panelWidth: CGFloat = 252
    static let transportBarHeight: CGFloat = 54
    static let tablePadX: CGFloat = 15

    // Track table column widths (fixed ones; middle columns flex)
    static let colNumWidth: CGFloat = 38
    static let colTimeWidth: CGFloat = 56
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension Font {
    /// Monospaced font for track numbers, durations, and technical metadata.
    static func konpoMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
