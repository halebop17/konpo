import SwiftUI
import AppKit

/// Center pane: the dense track table for the selected folder. In M1 metadata
/// columns are blank (filenames only); tags stream in at M3.
struct TrackListView: View {
    @Environment(AppModel.self) private var app
    var focus: FocusState<FocusedPane?>.Binding

    // User-adjustable column widths (drag the header dividers). Title and Artist
    // have explicit widths; Album absorbs the remaining space so the total
    // always fits the window — widening a column narrows Album, not the window.
    @AppStorage("colTitleWidth") private var titleWidth: Double = 260
    @AppStorage("colArtistWidth") private var artistWidth: Double = 160
    @State private var tableWidth: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            if app.tracks.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(app.tracks.enumerated()), id: \.element.id) { index, track in
                                row(index: index, track: track)
                                    .id(track.url)
                            }
                        }
                    }
                    .onChange(of: app.selectedTrack?.url) { _, url in
                        if let url { withAnimation(.linear(duration: 0.1)) { proxy.scrollTo(url, anchor: .center) } }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.window)
        .contentShape(Rectangle())
        .onTapGesture { focus.wrappedValue = .tracks }
        .focusable()
        .focusEffectDisabled()
        .focused(focus, equals: .tracks)
        .onKeyPress(.upArrow) { app.moveSelection(-1); return .handled }
        .onKeyPress(.downArrow) { app.moveSelection(1); return .handled }
        .onKeyPress(.leftArrow) { focus.wrappedValue = .folders; return .handled }
        .onKeyPress(.tab) { focus.wrappedValue = .folders; return .handled }
        .onKeyPress(.return) { app.playSelected(); return .handled }
    }

    private var header: some View {
        columns(
            num: Text("#"),
            title: Text("TITLE"),
            artist: Text("ARTIST"),
            album: Text("ALBUM"),
            time: Text("TIME"),
            resizable: true
        )
        .font(.system(size: Theme.fontSize - 2, weight: .semibold))
        .kerning(0.6)
        .foregroundStyle(Theme.dim)
        .padding(.vertical, 7)
        .padding(.horizontal, Theme.tablePadX)
        .overlay(alignment: .bottom) { Theme.separator.frame(height: 1) }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { tableWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, w in tableWidth = w }
            }
        )
    }

    private func row(index: Int, track: Track) -> some View {
        let playing = app.nowPlaying?.url == track.url
        let selected = app.selectedTrack?.url == track.url
        // Accent is reserved for the playing row; selection is a neutral
        // highlight so the two never both read as "active".
        let number = track.trackNumber.map { String(format: "%02d", $0) } ?? String(format: "%02d", index + 1)
        return columns(
            num: Text(playing ? "▶" : number)
                .font(.konpoMono(Theme.fontSize - 1))
                .foregroundStyle(playing ? app.accent : Theme.dim),
            title: Text(track.title)
                .font(.system(size: Theme.fontSize, weight: playing ? .semibold : .regular))
                .foregroundStyle(playing ? app.accent : Theme.text),
            artist: Text(dashed(track.artist))
                .font(.system(size: Theme.fontSize - 0.5))
                .foregroundStyle(Theme.muted),
            album: Text(dashed(track.album))
                .font(.system(size: Theme.fontSize - 0.5))
                .foregroundStyle(Theme.muted),
            time: Text(dashed(track.durationText))
                .font(.konpoMono(Theme.fontSize - 1))
                .foregroundStyle(Theme.muted)
        )
        .lineLimit(1)
        .padding(.horizontal, Theme.tablePadX)
        .frame(height: Theme.rowHeight)
        .frame(maxWidth: .infinity)
        .background(playing ? app.accentTint : (selected ? app.highlightSelection : .clear))
        .overlay(alignment: .leading) {
            if playing { app.accent.frame(width: 2) }
        }
        .overlay(alignment: .bottom) { Theme.separator.frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { app.play(track) }
        .onTapGesture(count: 1) { app.selectedTrack = track; focus.wrappedValue = .tracks }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { app.play(track) }
        .contextMenu { trackMenu(track) }
    }

    /// Right-click menu: playlists listed inline for a fast one-click add.
    @ViewBuilder private func trackMenu(_ track: Track) -> some View {
        Button("Play") { app.play(track) }
        Divider()
        if !app.playlists.playlists.isEmpty {
            Section("Add to Playlist") {
                ForEach(app.playlists.playlists) { playlist in
                    Button(playlist.name) { app.addToPlaylist(track, playlist: playlist) }
                }
            }
        }
        Button("New Playlist…") { app.beginNewPlaylist(with: track) }
        if app.sidebarMode == .playlists, let playlist = app.selectedPlaylist {
            Divider()
            Button("Remove from Playlist", role: .destructive) {
                app.removeFromPlaylist(track, playlist: playlist)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text(emptyMessage)
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyMessage: String {
        if app.sidebarMode == .playlists {
            return app.selectedPlaylist == nil ? "Select a playlist" : "Playlist is empty"
        }
        return app.selectedFolder == nil ? "Select a folder" : "No audio files"
    }

    private func dashed(_ value: String) -> String { value.isEmpty ? "—" : value }

    /// Shared 5-column layout keeps the header and rows aligned. `resizable`
    /// (header only) adds draggable dividers after Title and Artist.
    private func columns(num: Text, title: Text, artist: Text, album: Text, time: Text,
                         resizable: Bool = false) -> some View {
        let (tW, aW) = effectiveWidths()
        return HStack(spacing: 8) {
            num.frame(width: Theme.colNumWidth, alignment: .leading)
            title.frame(width: tW, alignment: .leading)
                .overlay(alignment: .trailing) {
                    if resizable {
                        ResizeHandle(width: $titleWidth, minW: 90,
                                     maxW: { maxTitleArtistSum() - artistWidth },
                                     begin: { normalizeWidths(); return titleWidth })
                    }
                }
            artist.frame(width: aW, alignment: .leading)
                .overlay(alignment: .trailing) {
                    if resizable {
                        ResizeHandle(width: $artistWidth, minW: 60,
                                     maxW: { maxTitleArtistSum() - titleWidth },
                                     begin: { normalizeWidths(); return artistWidth })
                    }
                }
            album.frame(minWidth: 40, maxWidth: .infinity, alignment: .leading)
            time.frame(width: Theme.colTimeWidth, alignment: .trailing)
        }
    }

    /// Sync stored widths to what's actually displayed. They drift apart when
    /// the window shrinks (effectiveWidths scales the display down); resizing
    /// must start from the displayed value or the max clamp is wrong.
    private func normalizeWidths() {
        let (t, a) = effectiveWidths()
        titleWidth = t
        artistWidth = a
    }

    /// Widths clamped so Title+Artist never crowd out Album / push Time off-screen.
    private func effectiveWidths() -> (Double, Double) {
        let maxSum = maxTitleArtistSum()
        var t = titleWidth, a = artistWidth
        if t + a > maxSum, t + a > 0 {
            let scale = maxSum / (t + a)
            t *= scale; a *= scale
        }
        return (t, a)
    }

    private func maxTitleArtistSum() -> Double {
        guard tableWidth > 0 else { return titleWidth + artistWidth }
        // fixed = #, Time, 4 inter-column gaps, horizontal padding, min Album.
        let fixed = Double(Theme.colNumWidth + Theme.colTimeWidth) + 32 + Double(Theme.tablePadX * 2) + 60
        return Swift.max(160, Double(tableWidth) - fixed)
    }
}

/// A thin draggable divider that resizes the column to its left.
///
/// The drag MUST use global coordinates: the handle sits on the column edge and
/// moves as the width changes, so a local-space translation feeds the movement
/// back into itself — the width oscillates every frame (jitter) and the clamp
/// slams it into the minimum (columns that refuse to widen again).
private struct ResizeHandle: View {
    @Binding var width: Double
    let minW: Double
    /// Live upper bound (depends on the sibling column's width).
    let maxW: () -> Double
    /// Called once when a drag begins; returns the width to measure from.
    let begin: () -> Double

    @State private var startWidth: Double?
    @GestureState private var isDragging = false

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 16)
            .overlay { Theme.separator.frame(width: 1) }
            .contentShape(Rectangle())
            .offset(x: 8)
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .updating($isDragging) { _, state, _ in state = true }
                    .onChanged { v in
                        let start: Double
                        if let s = startWidth {
                            start = s
                        } else {
                            start = begin()
                            startWidth = start
                        }
                        let hi = Swift.max(minW, maxW())
                        width = Swift.min(Swift.max(start + Double(v.translation.width), minW), hi)
                    }
                    .onEnded { _ in startWidth = nil }
            )
            // @GestureState resets on cancellation too (onEnded doesn't fire then),
            // so this catches interrupted drags and keeps the next one clean.
            .onChange(of: isDragging) { _, dragging in
                if !dragging { startWidth = nil }
            }
    }
}
