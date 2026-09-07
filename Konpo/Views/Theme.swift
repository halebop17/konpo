import SwiftUI

/// Design tokens from the Konpo mockup (docs/plan.md, Konpo (standalone).html).
enum Theme {
    /// Raw palette values. Kept as hex alongside the `Color`s so the contrast
    /// tests can measure them — `Color` gives no way back to its components.
    enum Hex {
        static let window: UInt32 = 0x1B1C1E
        static let titlebar: UInt32 = 0x212224
        static let sidebar: UInt32 = 0x1E1F22
        static let panel: UInt32 = 0x1D1E21
        static let text: UInt32 = 0xD8D9DD
        /// Secondary content — artist, album, durations. Carries real
        /// information, so it is held to the 4.5:1 body-text ratio.
        static let muted: UInt32 = 0x8A8C94
        /// Tertiary labels — column headers, track numbers, disc headers. Held to
        /// the 3:1 large/secondary ratio rather than 4.5:1, so the table stays
        /// visually quiet without becoming unreadable.
        static let dim: UInt32 = 0x6B6D75
        static let onAccent: UInt32 = 0x1B1C1E
    }

    // Colors — fixed dark charcoal base, amber accent
    static let accent = Color(hex: 0xF5A623)
    static let window = Color(hex: Hex.window)
    static let titlebar = Color(hex: Hex.titlebar)
    static let sidebar = Color(hex: Hex.sidebar)
    static let panel = Color(hex: Hex.panel)
    static let text = Color(hex: Hex.text)
    static let muted = Color(hex: Hex.muted)
    static let dim = Color(hex: Hex.dim)
    static let separator = Color.white.opacity(0.06)
    static let sliderTrack = Color.white.opacity(0.13)
    /// Text color used on top of the accent (accent is light amber → dark text)
    static let onAccent = Color(hex: Hex.onAccent)
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

// MARK: - Contrast

extension Theme {
    /// WCAG 2.1 relative luminance of a packed sRGB colour.
    static func relativeLuminance(_ hex: UInt32) -> Double {
        func channel(_ raw: UInt32) -> Double {
            let c = Double(raw) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let r = channel((hex >> 16) & 0xFF)
        let g = channel((hex >> 8) & 0xFF)
        let b = channel(hex & 0xFF)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// WCAG contrast ratio between two packed sRGB colours (1…21).
    static func contrastRatio(_ a: UInt32, _ b: UInt32) -> Double {
        let la = relativeLuminance(a)
        let lb = relativeLuminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
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
