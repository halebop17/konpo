import SwiftUI

/// Center pane in Albums view: a grid of album covers for every album under the
/// folder selected in the tree. Clicking (or Return on) an album plays it —
/// the folder tree stays as the scope, so picking "Rock" shows Rock's albums and
/// picking the root shows them all. Covers load lazily, only when scrolled into
/// view, to stay as light as the rest of Konpo.
struct AlbumGridView: View {
    @Environment(AppModel.self) private var app
    var focus: FocusState<FocusedPane?>.Binding

    @AppStorage("albumHideTree") private var hideTree = false
    @State private var selectedIndex: Int?
    @State private var columnCount = 1
    @FocusState private var searchFocused: Bool

    /// Albums after the live search filter (by folder name).
    ///
    /// Held in state rather than computed: `body` reads this several times per
    /// evaluation (the count label, the empty check, the grid, and each key
    /// handler), so a computed property re-filtered the entire library on every
    /// render — including every scroll-driven one.
    @State private var filtered: [Album] = []

    private let cellMin: CGFloat = 156
    private let spacing: CGFloat = 16
    private let outerPad: CGFloat = 16

    private func applyFilter() {
        let query = app.albumSearchText.trimmingCharacters(in: .whitespaces).lowercased()
        filtered = query.isEmpty ? app.albums : app.albums.filter { $0.searchName.contains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.window)
        .contentShape(Rectangle())
        .onTapGesture { focus.wrappedValue = .tracks }
        .focusable()
        .focusEffectDisabled()
        .focused(focus, equals: .tracks)
        .onKeyPress(.upArrow) { move(-columnCount) }
        .onKeyPress(.downArrow) { move(columnCount) }
        .onKeyPress(.leftArrow) { moveLeft() }
        .onKeyPress(.rightArrow) { move(1) }
        .onKeyPress(.return) { playSelected() }
        // Only when the grid itself has focus — the search field keeps its spaces.
        .onKeyPress(.space) { app.playPause(); return .handled }
        .onKeyPress(.tab) { if !hideTree { focus.wrappedValue = .folders }; return .handled }
        .onChange(of: app.albumSearchFocusRequest) { _, _ in searchFocused = true }
        .onAppear { applyFilter() }
        .onChange(of: app.albums) { _, _ in selectedIndex = nil; applyFilter() }
        .onChange(of: app.albumSearchText) { _, _ in selectedIndex = nil; applyFilter() }
    }

    // MARK: - Top bar (hide-tree toggle + search)

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { hideTree.toggle() }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 12))
                    .foregroundStyle(hideTree ? Theme.muted : app.accent)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(hideTree ? "Show folder tree" : "Hide folder tree")

            searchField

            Spacer(minLength: 0)

            if !filtered.isEmpty {
                Text("\(filtered.count) album\(filtered.count == 1 ? "" : "s")")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.dim)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Theme.separator.frame(height: 1) }
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(Theme.dim)
            TextField("Search", text: Binding(get: { app.albumSearchText },
                                              set: { app.albumSearchText = $0 }))
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Theme.text)
                .focused($searchFocused)
                .frame(width: 150)
                .onSubmit {
                    searchFocused = false
                    focus.wrappedValue = .tracks
                    if selectedIndex == nil, !filtered.isEmpty { selectedIndex = 0 }
                }
            if !app.albumSearchText.isEmpty {
                Button { app.albumSearchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.dim)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.sidebar, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(searchFocused ? app.accent.opacity(0.5) : Theme.separator, lineWidth: 1)
        }
    }

    // MARK: - Grid content

    private var content: some View {
        GeometryReader { geo in
            let cols = max(1, Int((geo.size.width - 2 * outerPad + spacing) / (cellMin + spacing)))
            Group {
                if app.isLoadingAlbums && app.albums.isEmpty {
                    message("Loading albums…")
                } else if filtered.isEmpty {
                    message(app.albums.isEmpty ? "No albums here" : "No matches")
                } else {
                    grid(cols: cols)
                }
            }
            .onAppear { columnCount = cols }
            .onChange(of: cols) { _, newValue in columnCount = newValue }
        }
    }

    private func grid(cols: Int) -> some View {
        let items = filtered
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: cols),
                          spacing: spacing) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, album in
                        cell(album, index: index).id(album.id)
                    }
                }
                .padding(outerPad)
            }
            .onChange(of: selectedIndex) { _, index in
                if let index, items.indices.contains(index) {
                    withAnimation(.linear(duration: 0.1)) { proxy.scrollTo(items[index].id, anchor: .center) }
                }
            }
        }
    }

    private func cell(_ album: Album, index: Int) -> some View {
        let playing = app.nowPlaying.map { album.trackURLs.contains($0.url) } ?? false
        let selected = selectedIndex == index
        return VStack(alignment: .leading, spacing: 7) {
            AlbumArtView(url: album.representativeTrackURL, albumFolder: album.folderURL, maxPixel: 256)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(playing ? app.accent : Theme.separator, lineWidth: playing ? 2 : 1)
                }
                .overlay(alignment: .bottomLeading) {
                    if playing {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(app.onAccent)
                            .padding(4)
                            .background(app.accent, in: RoundedRectangle(cornerRadius: 4))
                            .padding(6)
                    }
                }
            Text(album.name)
                .font(.system(size: Theme.fontSize, weight: playing ? .semibold : .regular))
                .foregroundStyle(playing ? app.accent : Theme.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(7)
        .background(selected ? app.highlightSelection : .clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: 8).strokeBorder(app.accent.opacity(0.55), lineWidth: 1.5)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            selectedIndex = index
            focus.wrappedValue = .tracks
            app.playAlbum(album)
        }
        .help(album.name)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Keyboard navigation

    private func move(_ delta: Int) -> KeyPress.Result {
        let items = filtered
        guard !items.isEmpty else { return .ignored }
        let current = selectedIndex ?? -1
        selectedIndex = current < 0 ? 0 : min(max(current + delta, 0), items.count - 1)
        return .handled
    }

    /// Left moves one cell back, but at the left edge it hands focus to the tree
    /// (mirroring the track list's ← behaviour), unless the tree is hidden.
    private func moveLeft() -> KeyPress.Result {
        let items = filtered
        guard !items.isEmpty else {
            if !hideTree { focus.wrappedValue = .folders }
            return .handled
        }
        let current = selectedIndex ?? 0
        if !hideTree, current % columnCount == 0 {
            focus.wrappedValue = .folders
            return .handled
        }
        return move(-1)
    }

    private func playSelected() -> KeyPress.Result {
        let items = filtered
        guard let index = selectedIndex, items.indices.contains(index) else { return .ignored }
        app.playAlbum(items[index])
        return .handled
    }
}
