import SwiftUI

/// Playlist list shown in the sidebar when in Playlists mode.
struct PlaylistSidebar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if app.playlists.playlists.isEmpty {
            VStack(spacing: 8) {
                Text("No playlists")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                Text("Right-click a track →\nAdd to Playlist")
                    .font(.system(size: 11))
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
    @Environment(AppModel.self) private var app
    let playlist: Playlist

    private var isSelected: Bool { app.selectedPlaylist?.id == playlist.id }

    var body: some View {
        Button {
            app.selectPlaylist(playlist)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? app.accent : Theme.dim)
                    .frame(width: 14)
                Text(playlist.name)
                    .font(.system(size: Theme.fontSize, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? app.accent : Theme.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Text("\(playlist.trackPaths.count)")
                    .font(.konpoMono(10))
                    .foregroundStyle(Theme.dim)
            }
            .padding(.leading, 12)
            .padding(.trailing, 10)
            .frame(height: Theme.rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? app.accentSelection : .clear)
            .overlay(alignment: .leading) {
                if isSelected { app.accent.frame(width: 2) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete Playlist", role: .destructive) { app.deletePlaylist(playlist) }
        }
    }
}
