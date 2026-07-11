import SwiftUI

/// Preferences window (⌘,): the user-selectable accent colors.
struct SettingsView: View {
    @Environment(AppModel.self) private var app

    private let presets: [(name: String, hex: UInt32)] = [
        ("Amber", 0xF5A623), ("Off-white", 0xE8E9EC), ("Blue", 0x0A84FF),
        ("Green", 0x2F9E63), ("Red", 0xFF5F57), ("Purple", 0xBF5AF2),
    ]

    var body: some View {
        @Bindable var app = app
        Form {
            Section {
                ColorPicker("Accent color", selection: $app.accentColor, supportsOpacity: false)
                swatchRow(selected: app.accentHex) { app.accentHex = $0 }
            } footer: {
                Text("Highlights the playing track, selections, and controls.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ColorPicker("2nd accent", selection: $app.accent2Color, supportsOpacity: false)
                swatchRow(selected: app.accent2Hex) { app.accent2Hex = $0 }
            } footer: {
                Text("Marks the keyboard-focus edge when the track list is focused (the folder list uses the primary accent).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ColorPicker("Track highlight", selection: $app.highlightColor, supportsOpacity: false)
                swatchRow(selected: app.highlightHex) { app.highlightHex = $0 }
            } footer: {
                Text("Tints the selected row in the track list.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 460)
    }

    private func swatchRow(selected: UInt32, set: @escaping (UInt32) -> Void) -> some View {
        HStack(spacing: 10) {
            ForEach(presets, id: \.hex) { preset in
                Button { set(preset.hex) } label: {
                    Circle()
                        .fill(Color(hex: preset.hex))
                        .frame(width: 22, height: 22)
                        .overlay {
                            Circle().strokeBorder(
                                selected == preset.hex ? Color.primary : Color.secondary.opacity(0.35),
                                lineWidth: selected == preset.hex ? 2.5 : 1)
                        }
                }
                .buttonStyle(.plain)
                .help(preset.name)
            }
        }
        .padding(.vertical, 2)
    }
}
