import SwiftUI
import WebKit

/// Lets the SwiftUI control bar drive the JS visualizer (preset cycling).
@MainActor
final class VisualizerController: ObservableObject {
    weak var webView: WKWebView?
    func next() { webView?.evaluateJavaScript("window.nextPreset && window.nextPreset()") }
    func previous() { webView?.evaluateJavaScript("window.prevPreset && window.prevPreset()") }
    func random() { webView?.evaluateJavaScript("window.randomPreset && window.randomPreset()") }
}

/// The optional MilkDrop-style visualizer window (Butterchurn in a WebView, fed
/// live audio from the player's engine tap). The WebView exists only while the
/// window is open: `alive` drops to false on window close, which removes the
/// WebView from the hierarchy so it (and its WebKit helper processes) is freed.
struct VisualizerView: View {
    @Environment(AppModel.self) private var app
    @StateObject private var controller = VisualizerController()
    @State private var showControls = true
    @State private var alive = true

    var body: some View {
        ZStack(alignment: .bottom) {
            if alive {
                VisualizerWebView(buffer: app.player.visualizerBuffer,
                                  controller: controller,
                                  presetFolder: app.visualizerPresetFolder,
                                  onChooseFolder: { app.chooseVisualizerPresetFolder() },
                                  onUseBuiltin: { app.useBuiltInVisualizerPresets() },
                                  hasCustomFolder: { app.visualizerPresetFolder != nil })
                    .background(.black)
            } else {
                Color.black
            }

            if showControls && alive {
                HStack(spacing: 18) {
                    controlButton("backward.end.fill") { controller.previous() }
                    controlButton("shuffle") { controller.random() }
                    controlButton("forward.end.fill") { controller.next() }
                    Divider().frame(height: 18).overlay(.white.opacity(0.2))
                    Menu {
                        Button("Choose Preset Folder…") { app.chooseVisualizerPresetFolder() }
                        if app.visualizerPresetFolder != nil {
                            Divider()
                            Button("Use Built-in Presets") { app.useBuiltInVisualizerPresets() }
                        }
                    } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.black.opacity(0.5), in: Capsule())
                .overlay { Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1) }
                .padding(.bottom, 20)
                .transition(.opacity)
            }
        }
        .frame(minWidth: 480, minHeight: 320)
        .background(.black)
        .ignoresSafeArea()
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) { showControls = hovering }
        }
        .onAppear {
            alive = true
            app.player.startVisualizerTap()
        }
        .onDisappear { app.player.stopVisualizerTap() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            // When the visualizer window closes, tear the WebView down so its
            // WebContent/GPU/Networking helper processes exit instead of lingering.
            guard let win = note.object as? NSWindow, win.title == "Visualizer" else { return }
            app.player.stopVisualizerTap()
            alive = false
        }
    }

    private func controlButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// WKWebView subclass that shows Konpo's own right-click menu (pick a preset
/// folder) instead of the default web context menu.
private final class VizWebView: WKWebView {
    var onChooseFolder: (() -> Void)?
    var onUseBuiltin: (() -> Void)?
    var hasCustomFolder: () -> Bool = { false }

    // WKWebView builds its context menu through its own path, so `menu(for:)`
    // is bypassed — `willOpenMenu` is the hook that actually lets us replace it.
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        menu.removeAllItems()
        let choose = NSMenuItem(title: "Choose Preset Folder…",
                                action: #selector(chooseFolder), keyEquivalent: "")
        choose.target = self
        menu.addItem(choose)
        if hasCustomFolder() {
            let builtin = NSMenuItem(title: "Use Built-in Presets",
                                     action: #selector(useBuiltin), keyEquivalent: "")
            builtin.target = self
            menu.addItem(builtin)
        }
    }
    @objc private func chooseFolder() { onChooseFolder?() }
    @objc private func useBuiltin() { onUseBuiltin?() }
}

private struct VisualizerWebView: NSViewRepresentable {
    let buffer: VisualizerAudioBuffer
    let controller: VisualizerController
    let presetFolder: String?
    var onChooseFolder: () -> Void = {}
    var onUseBuiltin: () -> Void = {}
    var hasCustomFolder: () -> Bool = { false }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        // JS asks for a preset by filename; native reads it and pushes it back.
        config.userContentController.add(context.coordinator, name: "konpo")

        let web = VizWebView(frame: .zero, configuration: config)
        web.onChooseFolder = onChooseFolder
        web.onUseBuiltin = onUseBuiltin
        web.hasCustomFolder = hasCustomFolder
        web.navigationDelegate = context.coordinator
        controller.webView = web
        context.coordinator.folder = presetFolder

        if let url = Self.htmlURL() {
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        context.coordinator.start(web: web, buffer: buffer)
        return web
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.update(folder: presetFolder, web: nsView)
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        // Full teardown so the WebView deallocates and its helper processes exit.
        coordinator.stop()
        nsView.stopLoading()
        nsView.navigationDelegate = nil
        nsView.configuration.userContentController.removeAllScriptMessageHandlers()
        nsView.loadHTMLString("", baseURL: nil)
        nsView.removeFromSuperview()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private static func htmlURL() -> URL? {
        Bundle.main.url(forResource: "visualizer", withExtension: "html", subdirectory: "web")
            ?? Bundle.main.url(forResource: "visualizer", withExtension: "html")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private var timer: Timer?
        private weak var web: WKWebView?
        var folder: String?
        private var loaded = false

        func start(web: WKWebView, buffer: VisualizerAudioBuffer) {
            self.web = web
            let timer = Timer(timeInterval: 1.0 / 50.0, repeats: true) { [weak web] _ in
                guard let web else { return }
                let samples = buffer.drain()
                guard !samples.isEmpty else { return }
                var ints = [Int16](repeating: 0, count: samples.count)
                for i in 0..<samples.count {
                    ints[i] = Int16(max(-1, min(1, samples[i])) * 32767)
                }
                let b64 = ints.withUnsafeBytes { Data($0) }.base64EncodedString()
                web.evaluateJavaScript("window.pushAudio && window.pushAudio('\(b64)')")
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }

        func stop() { timer?.invalidate(); timer = nil }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            sendPresets(webView)
        }

        func update(folder newFolder: String?, web: WKWebView) {
            guard newFolder != folder else { return }
            folder = newFolder
            if loaded { sendPresets(web) }
        }

        /// JS requested a preset by filename — read the .json and push it back
        /// base64-encoded (no fetch, no CORS, no in-app conversion).
        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let name = message.body as? String, let folder,
                  let web = message.webView else { return }
            let nameJSON = Self.jsString(name)
            let fileURL = URL(fileURLWithPath: folder, isDirectory: true).appendingPathComponent(name)
            guard let data = try? Data(contentsOf: fileURL) else {
                web.evaluateJavaScript("window.__recvError(\(nameJSON), 'read failed')")
                return
            }
            let b64 = data.base64EncodedString()
            web.evaluateJavaScript("window.__recvPreset(\(nameJSON), '\(b64)')")
        }

        private func sendPresets(_ web: WKWebView) {
            guard let folder, let names = Self.presetNames(in: folder), !names.isEmpty,
                  let data = try? JSONEncoder().encode(names),
                  let json = String(data: data, encoding: .utf8) else {
                web.evaluateJavaScript("window.useBuiltinPresets && window.useBuiltinPresets()")
                return
            }
            web.evaluateJavaScript("window.loadCustomPresets && window.loadCustomPresets(\(json))")
        }

        /// Only .json presets are loaded — MilkDrop .milk files are pre-converted
        /// offline (scripts/convert-milkdrop-presets.js), keeping the app light.
        /// Recurses so a pack with category subfolders can be pointed at directly;
        /// names are folder-relative paths ("Fractal/foo.json").
        private static func presetNames(in folder: String) -> [String]? {
            let root = URL(fileURLWithPath: folder, isDirectory: true)
            guard let en = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]) else { return nil }
            var names: [String] = []
            for case let url as URL in en where url.pathExtension.lowercased() == "json" {
                let rel = url.path.replacingOccurrences(of: root.path + "/", with: "")
                names.append(rel)
            }
            return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }

        private static func jsString(_ s: String) -> String {
            let data = (try? JSONEncoder().encode(s)) ?? Data("\"\"".utf8)
            return String(data: data, encoding: .utf8) ?? "\"\""
        }
    }
}
