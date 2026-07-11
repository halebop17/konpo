import SwiftUI
import AppKit

/// Makes the standard window titlebar transparent and dark so it blends with the
/// app, while keeping the native title + toolbar on the traffic-light row.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { Self.configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { Self.configure(nsView.window) }
    }

    private static func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.styleMask.remove(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.backgroundColor = NSColor(srgbRed: 0x1B / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1)
    }
}
