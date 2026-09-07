import SwiftUI
import AppKit

/// Scene identifiers for the auxiliary windows.
///
/// Previously both the visualizer toggle and the visualizer's own close handler
/// found their window by comparing `NSWindow.title` to the literal "Visualizer",
/// which would silently stop working as soon as the app is localized.
enum WindowID {
    static let visualizer = "visualizer"
    static let artwork = "artwork"
}

extension NSWindow {
    /// SwiftUI encodes the scene id into the window's `identifier`, so this
    /// survives translation of the visible title.
    var isVisualizer: Bool {
        identifier?.rawValue.contains(WindowID.visualizer) ?? false
    }
}
