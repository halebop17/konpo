import SwiftUI
import AppKit

/// Which list the keyboard is driving. Tab flips between them.
enum FocusedPane: Hashable { case folders, tracks }

/// The main three-region layout: folder tree, track list, album-art panel, plus
/// the bottom transport bar. Sidebar width is user-resizable and persisted.
struct MainWindow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    @AppStorage("showArtPanel") private var showPanel = true
    @AppStorage("sidebarWidth") private var sidebarWidth: Double = 210
    /// Album-art panel width preset: 0 = small, 1 = medium, 2 = large.
    @AppStorage("artPanelSize") private var artPanelSize: Int = 1
    @State private var dragStartWidth: Double?
    /// Non-nil while scrubbing the seek bar (seconds), so the elapsed label and
    /// fill track the drag instead of the live playhead.
    @State private var scrubSeconds: Double?
    @FocusState private var focus: FocusedPane?

    private static let minSidebar: Double = 150
    private static let maxSidebar: Double = 420
    private static let artSizes: [CGFloat] = [212, 260, 344]
    private var artPanelWidth: CGFloat { Self.artSizes[max(0, min(2, artPanelSize))] }

    var body: some View {
        @Bindable var app = app
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                SidebarView(focus: $focus)
                    .frame(width: sidebarWidth)
                    .overlay(alignment: .trailing) { focusEdge(.folders) }
                sidebarDivider
                TrackListView(focus: $focus)
                    .overlay(alignment: .leading) { focusEdge(.tracks) }
                if showPanel {
                    artPanel
                        .overlay(alignment: .leading) { Theme.separator.frame(width: 1) }
                }
            }
            .frame(maxHeight: .infinity)
            transportBar
        }
        .onAppear { if focus == nil { focus = .tracks } }
        .frame(minWidth: 720, minHeight: 480)
        .background(Theme.window)
        .background(WindowConfigurator())
        // The path is the native window title and the toggle a titlebar button —
        // both live in the titlebar row with the traffic lights (one row).
        .navigationTitle(titlePath)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    revealInFinder()
                } label: {
                    Image(systemName: "folder")
                }
                .help("Show in Finder")
                .disabled(currentDiskURL == nil)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    toggleVisualizer()
                } label: {
                    Image(systemName: "waveform")
                }
                .help("Toggle visualizer (⇧⌘V)")
                .keyboardShortcut("v", modifiers: [.command, .shift])
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showPanel.toggle()
                } label: {
                    Image(systemName: "sidebar.trailing")
                        .foregroundStyle(showPanel ? app.accent : Theme.muted)
                }
                .help("Toggle album art panel (⌘B)")
                .keyboardShortcut("b", modifiers: .command)
            }
        }
        .overlay(alignment: .top) { errorToast }
        .animation(.easeInOut(duration: 0.25), value: app.errorMessage)
        .alert("New Playlist", isPresented: $app.showNewPlaylistPrompt) {
            TextField("Name", text: $app.newPlaylistName)
            Button("Create") { app.confirmNewPlaylist() }
            Button("Cancel", role: .cancel) { app.cancelNewPlaylist() }
        } message: {
            Text("Enter a name for the new playlist.")
        }
    }

    // MARK: - Error toast

    @ViewBuilder private var errorToast: some View {
        if let message = app.errorMessage {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(app.accent)
                Text(message)
                    .foregroundStyle(Theme.text)
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Theme.titlebar, in: Capsule())
            .overlay { Capsule().strokeBorder(Theme.separator, lineWidth: 1) }
            .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
            .padding(.top, 40)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Keyboard focus

    /// A subtle dotted line on the inner edge of whichever pane the keyboard is
    /// driving — primary accent for folders, second accent for the track list.
    @ViewBuilder private func focusEdge(_ pane: FocusedPane) -> some View {
        if focus == pane {
            DottedEdge(color: pane == .folders ? app.accent : app.accent2)
                .frame(width: 2)
                .transition(.opacity)
        }
    }

    private func toggleVisualizer() {
        if let win = NSApp.windows.first(where: { $0.title == "Visualizer" && $0.isVisible }) {
            win.close()
        } else {
            openWindow(id: "visualizer")
        }
    }

    // MARK: - Resizable sidebar divider

    private var sidebarDivider: some View {
        ZStack {
            Color.clear
            Theme.separator.frame(width: 1)
        }
        .frame(width: 6)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let start = dragStartWidth ?? sidebarWidth
                    if dragStartWidth == nil { dragStartWidth = start }
                    sidebarWidth = min(max(start + value.translation.width, Self.minSidebar), Self.maxSidebar)
                }
                .onEnded { _ in dragStartWidth = nil }
        )
    }

    // MARK: - Title bar

    /// Compact window title: no app name, no full path — just the current
    /// track (or folder) and one folder level back, e.g. "CD1/Down Town".
    private var titlePath: String {
        if app.sidebarMode == .playlists {
            if let playlist = app.selectedPlaylist { return "♪ \(playlist.name)" }
            return "Playlists"
        }
        if let track = displayTrack {
            // "<folder> - <artist> - <title>", dropping any empty piece.
            let parent = track.url.deletingLastPathComponent().lastPathComponent
            let parts = [parent, track.artist, track.title].filter { !$0.isEmpty }
            return parts.joined(separator: " - ")
        }
        if let folder = app.selectedFolder {
            return oneLevel(folder.url, name: folder.name)
        }
        return "konpo"
    }

    private func oneLevel(_ url: URL, name: String) -> String {
        let parent = url.deletingLastPathComponent().lastPathComponent
        return parent.isEmpty ? name : "\(parent)/\(name)"
    }

    /// The folder on disk to reveal for the current track (or selected folder).
    private var currentDiskURL: URL? {
        displayTrack?.url ?? app.selectedFolder?.url
    }

    private func revealInFinder() {
        guard let url = currentDiskURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }


    // MARK: - Album art panel (placeholder art until M4)

    /// The panel reflects the playing track, falling back to the selected one.
    private var displayTrack: Track? { app.nowPlaying ?? app.selectedTrack }

    private func openArtworkFullSize() {
        guard let url = displayTrack?.url else { return }
        app.artworkFullURL = url
        openWindow(id: "artwork")
    }

    private var artPanel: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                AlbumArtView(url: displayTrack?.url, maxPixel: 900)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Theme.separator, lineWidth: 1)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                    .onTapGesture { openArtworkFullSize() }
                    .onHover { hovering in
                        guard displayTrack != nil else { return }
                        if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                    .help("Open album art full size")
                Text(displayTrack?.title ?? "No selection")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(displayTrack == nil ? Theme.muted : Theme.text)
                    .lineLimit(2)
                    .padding(.top, 14)
                Text(dashed(displayTrack?.artist))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 3)

                VStack(spacing: 4) {
                    metaRow("ALBUM", dashed(displayTrack?.album))
                    metaRow("YEAR", dashed(displayTrack?.year))
                    metaRow("CODEC", displayTrack?.codec ?? displayTrack?.formatHint ?? "—")
                    metaRow("SAMPLE RATE", sampleRateText(displayTrack?.sampleRate))
                    metaRow("BIT DEPTH", displayTrack?.bitDepth.map { "\($0)-bit" } ?? "—")
                    metaRow("CHANNELS", channelText(displayTrack?.channels))
                    metaRow("DURATION", panelDuration)
                }
                .padding(.top, 12)
                .overlay(alignment: .top) { Theme.separator.frame(height: 1) }
                .padding(.top, 14)
            }
            .padding(16)
            }
            .frame(maxHeight: .infinity)
            // Size control pinned to the bottom so the album art stays anchored
            // at the top of the panel.
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                artSizeDots
                Spacer(minLength: 0)
            }
            .padding(.vertical, 9)
            .overlay(alignment: .top) { Theme.separator.frame(height: 1) }
        }
        .frame(width: artPanelWidth)
        .background(Theme.panel)
    }

    /// Three dots (small → large) that pick the art-panel width preset.
    private var artSizeDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(i == artPanelSize ? app.accent : Theme.dim)
                    .frame(width: CGFloat(5 + i * 2), height: CGFloat(5 + i * 2))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.18)) { artPanelSize = i }
                    }
                    .help(["Small", "Medium", "Large"][i])
            }
        }
    }

    private var panelDuration: String {
        if let np = app.nowPlaying, np.url == displayTrack?.url, app.player.duration > 0 {
            return timeString(app.player.duration)
        }
        return dashed(displayTrack?.durationText)
    }

    private func sampleRateText(_ hz: Double?) -> String {
        guard let hz, hz > 0 else { return "—" }
        return String(format: "%.1f kHz", hz / 1000)
    }

    private func channelText(_ count: Int?) -> String {
        switch count {
        case 1: return "1 · Mono"
        case 2: return "2 · Stereo"
        case .some(let c) where c > 0: return "\(c)"
        default: return "—"
        }
    }

    private func metaRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(key)
                .font(.system(size: 10.5))
                .kerning(0.5)
                .foregroundStyle(Theme.dim)
            Spacer(minLength: 0)
            Text(value)
                .font(.konpoMono(11))
                .foregroundStyle(Theme.text)
        }
    }

    private func dashed(_ value: String?) -> String {
        (value?.isEmpty == false) ? value! : "—"
    }

    // MARK: - Transport bar

    private var nowLine: String {
        guard let np = app.nowPlaying else { return "Nothing playing" }
        return np.artist.isEmpty ? np.title : "\(np.title) — \(np.artist)"
    }

    private var isPlaying: Bool { app.player.state == .playing }

    private var transportBar: some View {
        let duration = app.player.duration
        let displaySeconds = scrubSeconds ?? app.player.position
        let fraction = duration > 0 ? displaySeconds / duration : 0
        return HStack(spacing: 16) {
            if !showPanel {
                AlbumArtView(url: displayTrack?.url, maxPixel: 128)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Theme.separator, lineWidth: 1)
                    }
            }
            HStack(spacing: 10) {
                transportButton("backward.end.fill") { app.playPrevious() }
                Button {
                    app.playPause()
                } label: {
                    Circle()
                        .fill(app.accent)
                        .frame(width: 38, height: 38)
                        .overlay {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(app.onAccent)
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                transportButton("forward.end.fill") { app.playNext() }
            }
            // The title hugs its text (no reserved block), so the greedy seek
            // bar to its right soaks up all remaining width — the bar grows with
            // the window and there's never an empty gap. A long title is
            // truncated only once the bar would shrink below its minimum.
            Text(nowLine)
                .font(.system(size: 12))
                .foregroundStyle(app.nowPlaying == nil ? Theme.muted : Theme.text)
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(spacing: 9) {
                Text(timeString(displaySeconds))
                    .font(.konpoMono(11))
                    .foregroundStyle(Theme.muted)
                DraggableBar(fraction: fraction, fillColor: app.accent, showKnob: true,
                    hitHeight: 30,
                    onScrub: { frac in
                        if duration > 0 { scrubSeconds = frac * duration }
                    },
                    onCommit: { frac in
                        if duration > 0 { app.seek(to: frac * duration) }
                        scrubSeconds = nil
                    })
                Text(timeString(duration))
                    .font(.konpoMono(11))
                    .foregroundStyle(Theme.muted)
            }
            // Greedy so it fills wide windows, but a low floor so a narrow window
            // compresses the bar (and truncates the title) instead of pushing the
            // fixed controls — artwork, transport buttons, volume — off-screen.
            .frame(minWidth: 150, maxWidth: .infinity)
            .layoutPriority(-1)

            HStack(spacing: 7) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                DraggableBar(fraction: Double(app.player.volume), fillColor: Theme.muted, showKnob: false,
                    hitHeight: 22,
                    onScrub: { frac in app.player.volume = Float(frac) },
                    onCommit: { frac in app.player.volume = Float(frac) })
            }
            .frame(width: 96)
        }
        .padding(.horizontal, 16)
        .frame(height: Theme.transportBarHeight)
        .background(Theme.titlebar)
        .overlay(alignment: .top) { Theme.separator.frame(height: 1) }
    }

    private func transportButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15))
                .foregroundStyle(Theme.muted)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// A controlled progress/volume bar: click or drag to set. The visible track is
/// thin (4pt) but the clickable band fills `hitHeight`, so clicks slightly above
/// or below the line still register. `fraction` is owned by the parent.
private struct DraggableBar: View {
    var fraction: Double
    var fillColor: Color
    var showKnob: Bool
    var hitHeight: CGFloat = 22
    var onScrub: (Double) -> Void
    var onCommit: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let clamped = min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                Color.clear // fills the tall hit band
                Capsule().fill(Theme.sliderTrack).frame(height: 4)
                Capsule().fill(fillColor).frame(width: width * clamped, height: 4)
                if showKnob {
                    Circle()
                        .fill(.white)
                        .frame(width: 12, height: 12)
                        .shadow(color: .black.opacity(0.5), radius: 1.5, y: 1)
                        .position(x: width * clamped, y: geo.size.height / 2)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onScrub(min(max(value.location.x / width, 0), 1))
                    }
                    .onEnded { value in
                        onCommit(min(max(value.location.x / width, 0), 1))
                    }
            )
        }
        .frame(height: hitHeight)
    }
}

/// A vertical dotted line — the keyboard-focus marker between panes. Round dash
/// caps read as a column of small dots, quieter than a solid rule.
private struct DottedEdge: View {
    let color: Color

    var body: some View {
        GeometryReader { geo in
            Path { path in
                path.move(to: CGPoint(x: 1, y: 1))
                path.addLine(to: CGPoint(x: 1, y: geo.size.height - 1))
            }
            .stroke(color.opacity(0.8),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.5, 9.5]))
        }
        .frame(width: 2)
        .allowsHitTesting(false)
    }
}
