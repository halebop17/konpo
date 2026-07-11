import SwiftUI

@main
struct KonpoApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environment(app)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1056, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Folder…") { app.chooseRoot() }
                    .keyboardShortcut("o", modifiers: .command)
                Button("Refresh") { app.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
            }
            CommandMenu("Playback") {
                Button(app.player.state == .playing ? "Pause" : "Play") { app.playPause() }
                    .keyboardShortcut(.space, modifiers: [])
                // Return is handled contextually by the focused list (play the
                // selected track / jump into the track list), so no menu shortcut.
                Button("Play Selected") { app.playSelected() }
                Divider()
                Button("Next Track") { app.playNext() }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                Button("Previous Track") { app.playPrevious() }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Button("Seek Forward") {
                    app.seek(to: min(app.player.position + 10, app.player.duration))
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                Button("Seek Backward") {
                    app.seek(to: max(app.player.position - 10, 0))
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            }
        }

        Settings {
            SettingsView()
                .environment(app)
        }

        // Optional visualizer — created only when opened, so the base app is
        // unaffected until you ask for it.
        Window("Visualizer", id: "visualizer") {
            VisualizerView()
                .environment(app)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 900, height: 600)

        // Full-size album art — opened by clicking the art panel.
        Window("Album Art", id: "artwork") {
            ArtworkWindowView()
                .environment(app)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 640, height: 700)
    }
}
