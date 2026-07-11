import SwiftUI

/// Left sidebar: the lazy folder tree. Rows are flattened into a single list so
/// the LazyVStack stays lazy across the whole visible (expanded) tree.
struct FolderTreeView: View {
    @Environment(AppModel.self) private var app
    var focus: FocusState<FocusedPane?>.Binding

    var body: some View {
        if let root = app.tree.root {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(flatten(root), id: \.node.id) { entry in
                            FolderRowView(node: entry.node, depth: entry.depth, focus: focus)
                                .id(entry.node.url)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                // Keep the keyboard-selected folder visible.
                .onChange(of: app.selectedFolder?.url) { _, url in
                    if let url { withAnimation(.linear(duration: 0.1)) { proxy.scrollTo(url, anchor: .center) } }
                }
            }
        } else {
            emptyState
        }
    }

    /// Depth-first flatten of the currently expanded tree. Reading `isExpanded`
    /// and `children` here registers @Observable dependencies, so toggling a
    /// node re-renders the list.
    private func flatten(_ root: FileNode) -> [(node: FileNode, depth: Int)] {
        var out: [(FileNode, Int)] = []
        func walk(_ node: FileNode, _ depth: Int) {
            out.append((node, depth))
            if node.isExpanded, let children = node.children {
                for child in children { walk(child, depth + 1) }
            }
        }
        walk(root, 0)
        return out
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("No folder open")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
            Button {
                app.chooseRoot()
            } label: {
                Text("Open Folder…  ⌘O")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(app.accent)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

private struct FolderRowView: View {
    @Environment(AppModel.self) private var app
    let node: FileNode
    let depth: Int
    var focus: FocusState<FocusedPane?>.Binding

    private var isSelected: Bool { app.selectedFolder?.url == node.url }
    private var isLeaf: Bool { node.hasSubdirectories == false }

    var body: some View {
        Button {
            focus.wrappedValue = .folders
            app.selectFolder(node)
            // Directories with subfolders toggle on click; leaf album folders
            // just select (their tracks appear in the center pane).
            if node.hasSubdirectories != false {
                app.tree.toggle(node)
            }
        } label: {
            HStack(spacing: 6) {
                Text(icon)
                    .font(.system(size: isLeaf ? 9 : 8))
                    .foregroundStyle(isSelected ? app.accent : Theme.dim)
                    .frame(width: 11)
                Text(node.name)
                    .font(.system(size: Theme.fontSize, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? app.accent : Theme.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.leading, 10 + CGFloat(depth) * 15)
            .padding(.trailing, 8)
            .frame(height: Theme.rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? app.accentSelection : .clear)
            .overlay(alignment: .leading) {
                if isSelected { app.accent.frame(width: 2) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { folderMenu }
    }

    @ViewBuilder private var folderMenu: some View {
        if !app.playlists.playlists.isEmpty {
            Section("Add Folder to Playlist") {
                ForEach(app.playlists.playlists) { playlist in
                    Button(playlist.name) { app.addFolderToPlaylist(node, playlist: playlist) }
                }
            }
        }
        Button("New Playlist from Folder…") { app.beginNewPlaylist(withFolder: node) }
    }

    private var icon: String {
        if isLeaf { return "♪" }
        return node.isExpanded ? "▾" : "▸"
    }
}
