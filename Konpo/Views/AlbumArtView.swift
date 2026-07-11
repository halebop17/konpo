import SwiftUI
import AppKit

/// Displays a track's album art (embedded, or a cover/folder image), downscaled
/// off the main actor. Shows a music-note placeholder when there's none.
struct AlbumArtView: View {
    let url: URL?
    var maxPixel: Int = 600

    @Environment(AppModel.self) private var app
    @State private var image: NSImage?

    var body: some View {
        // `Color.clear` is a zero-minimum flexible view: it takes exactly the
        // frame the parent hands us (a square, in the art panel). The image is an
        // overlay, so its `scaledToFill` overflow can't enlarge the layout — and
        // `.clipped()` crops it to the square. A `scaledToFill` image placed
        // directly imposes a large minimum size that breaks this, which is why a
        // non-square cover was spilling out of the panel. The full, uncropped
        // image is still shown (letterboxed) in the click-to-open art window.
        Color.clear
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFill()
                } else {
                    ZStack {
                        Theme.sidebar
                        Image(systemName: "music.note")
                            .font(.system(size: 24))
                            .foregroundStyle(Theme.dim)
                    }
                }
            }
            .clipped()
            .task(id: url) { await load() }
    }

    private func load() async {
        image = nil
        guard let url else { return }
        let data = await app.metadata.artworkData(for: url, maxPixel: maxPixel)
        if Task.isCancelled { return }
        if let data, let img = NSImage(data: data) { image = img }
    }
}

/// Full-size album art window (opened by clicking the art panel). Shows the art
/// at high resolution, fit to the resizable window.
struct ArtworkWindowView: View {
    @Environment(AppModel.self) private var app
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Color.black
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.dim)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .task(id: app.artworkFullURL) { await load() }
    }

    private func load() async {
        image = nil
        guard let url = app.artworkFullURL else { return }
        let data = await app.metadata.artworkData(for: url, maxPixel: 2048)
        if Task.isCancelled { return }
        if let data, let img = NSImage(data: data) { image = img }
    }
}
