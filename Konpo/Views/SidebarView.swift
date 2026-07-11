import SwiftUI

/// Left sidebar shell: a Folders/Playlists mode switch in the header, then the
/// folder tree or the playlist list below.
struct SidebarView: View {
    @Environment(AppModel.self) private var app
    var focus: FocusState<FocusedPane?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if app.sidebarMode == .folders {
                FolderTreeView(focus: focus)
            } else {
                PlaylistSidebar()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.sidebar)
        .contentShape(Rectangle())
        .focusable()
        .focusEffectDisabled()
        .focused(focus, equals: .folders)
        // Clicking anywhere in the sidebar makes it the keyboard target.
        .onTapGesture { focus.wrappedValue = .folders }
        .onKeyPress(.tab) { focus.wrappedValue = .tracks; return .handled }
        .onKeyPress(.upArrow) { folderKey { app.moveFolderSelection(-1) } }
        .onKeyPress(.downArrow) { folderKey { app.moveFolderSelection(1) } }
        .onKeyPress(.rightArrow) {
            folderKey { if !app.expandSelectedFolder() { focus.wrappedValue = .tracks } }
        }
        .onKeyPress(.leftArrow) { folderKey { app.collapseOrParent() } }
        .onKeyPress(.return) { folderKey { focus.wrappedValue = .tracks } }
    }

    /// Folder-nav keys only apply in Folders mode; otherwise let them pass.
    private func folderKey(_ action: () -> Void) -> KeyPress.Result {
        guard app.sidebarMode == .folders else { return .ignored }
        action()
        return .handled
    }

    private var header: some View {
        HStack(spacing: 12) {
            modeButton("FOLDERS", .folders)
            modeButton("PLAYLISTS", .playlists)
            Spacer(minLength: 0)
            if app.sidebarMode == .playlists {
                Button { app.beginNewPlaylist(with: nil) } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.muted)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New playlist")
                .padding(.trailing, 12)
            }
        }
        .padding(.init(top: 8, leading: 14, bottom: 7, trailing: 0))
    }

    private func modeButton(_ title: String, _ mode: AppModel.SidebarMode) -> some View {
        let active = app.sidebarMode == mode
        return Button { app.setSidebarMode(mode) } label: {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .kerning(0.8)
                .foregroundStyle(active ? app.accent : Theme.dim)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
