import Foundation

/// Every UserDefaults key the app touches, in one place.
///
/// They were previously spelled out as string literals across four files plus
/// six `@AppStorage` declarations in views — `albumHideTree` deliberately
/// duplicated across two of them — with nothing to catch a typo or tell you
/// what the full set was.
enum Defaults {

    /// SwiftUI's `@AppStorage` needs the key itself, so views reference these
    /// constants directly; the imperative accessors below use them too.
    enum Key {
        static let rootFolder = "rootFolderPath"
        static let lastFolder = "lastFolderPath"
        static let lastPlaylistID = "lastPlaylistID"
        static let viewMode = "viewMode"
        static let volume = "volume"
        static let visualizerPresetFolder = "vizPresetFolder"
        static let accentHex = "accentHex"
        static let accent2Hex = "accent2Hex"
        static let highlightHex = "highlightHex"

        // View-local layout state, read and written through @AppStorage.
        static let showArtPanel = "showArtPanel"
        static let sidebarWidth = "sidebarWidth"
        static let artPanelSize = "artPanelSize"
        static let albumHideTree = "albumHideTree"
        static let columnTitleWidth = "colTitleWidth"
        static let columnArtistWidth = "colArtistWidth"
    }

    private static var store: UserDefaults { .standard }

    static var rootFolderPath: String? {
        get { store.string(forKey: Key.rootFolder) }
        set { store.set(newValue, forKey: Key.rootFolder) }
    }

    static var lastFolderPath: String? {
        get { store.string(forKey: Key.lastFolder) }
        set { store.set(newValue, forKey: Key.lastFolder) }
    }

    static var lastPlaylistID: String? {
        get { store.string(forKey: Key.lastPlaylistID) }
        set { store.set(newValue, forKey: Key.lastPlaylistID) }
    }

    static var viewMode: String? {
        get { store.string(forKey: Key.viewMode) }
        set { store.set(newValue, forKey: Key.viewMode) }
    }

    static var volume: Float? {
        get { store.object(forKey: Key.volume) as? Float }
        set { store.set(newValue, forKey: Key.volume) }
    }

    /// nil means "use the built-in presets".
    static var visualizerPresetFolder: String? {
        get { store.string(forKey: Key.visualizerPresetFolder) }
        set {
            if let newValue { store.set(newValue, forKey: Key.visualizerPresetFolder) }
            else { store.removeObject(forKey: Key.visualizerPresetFolder) }
        }
    }

    static var accentHex: UInt32? {
        get { colour(Key.accentHex) }
        set { setColour(newValue, Key.accentHex) }
    }

    static var accent2Hex: UInt32? {
        get { colour(Key.accent2Hex) }
        set { setColour(newValue, Key.accent2Hex) }
    }

    static var highlightHex: UInt32? {
        get { colour(Key.highlightHex) }
        set { setColour(newValue, Key.highlightHex) }
    }

    /// Colours are stored as Int (UserDefaults has no UInt32). The range check
    /// keeps a corrupt or hand-edited value from trapping the UInt32 conversion.
    private static func colour(_ key: String) -> UInt32? {
        guard let raw = store.object(forKey: key) as? Int,
              raw >= 0, raw <= 0xFF_FFFF else { return nil }
        return UInt32(raw)
    }

    private static func setColour(_ value: UInt32?, _ key: String) {
        guard let value else { return }
        store.set(Int(value), forKey: key)
    }
}
