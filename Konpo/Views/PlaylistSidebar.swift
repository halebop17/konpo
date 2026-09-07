import SwiftUI

/// Playlist list shown in the sidebar when in Playlists mode.
struct PlaylistSidebar: View {
    @Environment(\.scaled) private var scaled
    @Environment(AppModel.self) private var app

    var body: some View {
        if app.playlists.playlists.isEmpty {
            VStack(spacing: 8) {
                Text("No playlists")
                    .font(scaled.font(12))
                    .foregroundStyle(Theme.muted)
                Text("Right-click a track →\nAdd to Playlist")
                    .font(scaled.font(11))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.dim)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(app.playlists.playlists) { playlist in
                        PlaylistRow(playlist: playlist)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct PlaylistRow: View {
    @Environment(\.scaled) private var scaled
    @Environment(AppModel.self) private var app
    let playlist: Playlist

    private var isSelected: Bool { app.selectedPlaylist?.id == playlist.id }

    var body: some View {
        Button {
            app.selectPlaylist(playlist)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "music.note.list")
                    .font(scaled.font(10))
                    .foregroundStyle(isSelected ? app.appearance.accent : Theme.dim)
                    .frame(width: 14)
                    .accessibilityHidden(true)
                Text(playlist.name)
                    .font(scaled.font(Theme.fontSize, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? app.appearance.accent : Theme.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Text("\(playlist.trackPaths.count)")
                    .font(scaled.mono(10))
                    .foregroundStyle(Theme.dim)
            }
            .padding(.leading, 12)
            .padding(.trailing, 10)
            .frame(height: scaled.rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? app.appearance.accentSelection : .clear)
            .overlay(alignment: .leading) {
                if isSelected { app.appearance.accent.frame(width: 2) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete Playlist", role: .destructive) { app.deletePlaylist(playlist) }
        }
        .accessibilityLabel(playlist.name)
        .accessibilityValue(Counts.tracks(playlist.trackPaths.count))
    }
}
