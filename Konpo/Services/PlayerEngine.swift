import Foundation
import AVFoundation

/// AVAudioEngine + AVAudioPlayerNode wrapper with gapless playback: the upcoming
/// track is pre-scheduled on the same node so it renders back-to-back with the
/// current one. Format changes between tracks fall back to a quick restart.
@MainActor
@Observable
final class PlayerEngine {
    enum PlaybackState { case stopped, playing, paused }

    private(set) var state: PlaybackState = .stopped
    private(set) var currentURL: URL?
    private(set) var duration: Double = 0
    private(set) var position: Double = 0

    var volume: Float = 0.8 {
        didSet {
            engine.mainMixerNode.outputVolume = volume
            UserDefaults.standard.set(volume, forKey: "volume")
        }
    }

    /// Playback moved to a new track (gapless advance or format-boundary restart).
    var onTrackChanged: ((URL) -> Void)?
    /// The queue ran out; playback stopped.
    var onPlaybackEnded: (() -> Void)?
    /// A file could not be opened/played.
    var onError: ((String) -> Void)?

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()

    /// Live audio for the (optional) visualizer window. The tap is only installed
    /// while the visualizer is open, so it costs nothing otherwise.
    let visualizerBuffer = VisualizerAudioBuffer()
    private var visualizerTapActive = false

    private typealias Item = (file: AVAudioFile, url: URL, duration: Double)
    private var current: Item?
    private var scheduledNext: Item?
    private var upcomingURL: URL?
    private var connectedFormat: AVAudioFormat?

    /// Bumped on play/stop/seek so completion callbacks from a superseded
    /// schedule are ignored. Gapless advance and setUpcoming do NOT bump it.
    private var generation = 0

    // Position baseline: position = baseSeconds + (sampleTime - baseSampleTime)/sr.
    private var baseSampleTime: AVAudioFramePosition?
    private var baseSeconds: Double = 0
    private var pendingBaseSeconds: Double?

    private var pollTask: Task<Void, Never>?

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: nil)
        let saved = UserDefaults.standard.object(forKey: "volume") as? Float ?? 0.8
        volume = saved
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleConfigurationChange() }
        }
    }

    // MARK: - Transport

    func play(url: URL) {
        generation += 1
        let gen = generation
        guard let file = try? AVAudioFile(forReading: url) else {
            onError?("Can't play \(url.lastPathComponent)")
            stop()
            return
        }
        let format = file.processingFormat
        let dur = format.sampleRate > 0 ? Double(file.length) / format.sampleRate : 0

        player.stop()
        scheduledNext = nil
        upcomingURL = nil
        if connectedFormat == nil || !compatible(connectedFormat!, format) {
            engine.connect(player, to: engine.mainMixerNode, format: format)
            connectedFormat = format
        }
        current = (file, url, dur)
        currentURL = url
        duration = dur
        scheduleFile(file, url: url, gen: gen)

        do {
            if !engine.isRunning { try engine.start() }
        } catch {
            stop()
            return
        }
        player.play()
        state = .playing
        setBaseline(seconds: 0)
        startPolling()
    }

    /// Hint the next track so it can be pre-scheduled for gapless playback.
    func setUpcoming(url: URL?) {
        upcomingURL = url
        scheduleUpcoming(gen: generation)
    }

    func playPauseToggle() {
        switch state {
        case .playing: pause()
        case .paused: resume()
        case .stopped: break
        }
    }

    func pause() {
        guard state == .playing else { return }
        player.pause()
        state = .paused
        stopPolling()
    }

    func resume() {
        guard state == .paused else { return }
        if !engine.isRunning { try? engine.start() }
        player.play()
        state = .playing
        startPolling()
    }

    func stop() {
        generation += 1
        player.stop()
        current = nil
        scheduledNext = nil
        currentURL = nil
        duration = 0
        position = 0
        state = .stopped
        stopPolling()
    }

    func seek(to seconds: Double) {
        guard let cur = current, duration > 0 else { return }
        generation += 1
        let gen = generation
        let sr = cur.file.processingFormat.sampleRate
        let clamped = min(max(seconds, 0), duration)
        let frame = AVAudioFramePosition(clamped * sr)
        let wasPlaying = (state == .playing)

        player.stop()
        scheduledNext = nil
        let remaining = cur.file.length - frame
        if remaining > 0 {
            scheduleSegment(cur.file, url: cur.url, from: frame, count: AVAudioFrameCount(remaining), gen: gen)
        }
        if wasPlaying {
            if !engine.isRunning { try? engine.start() }
            player.play()
            state = .playing
            startPolling()
        } else {
            state = .paused
        }
        setBaseline(seconds: clamped)
        scheduleUpcoming(gen: gen) // re-arm gapless next after the reschedule
    }

    // MARK: - Scheduling

    private func scheduleUpcoming(gen: Int) {
        guard state == .playing || state == .paused,
              scheduledNext == nil,
              let next = upcomingURL,
              let format = connectedFormat,
              let file = try? AVAudioFile(forReading: next),
              compatible(file.processingFormat, format) else { return }
        let dur = file.processingFormat.sampleRate > 0 ? Double(file.length) / file.processingFormat.sampleRate : 0
        scheduledNext = (file, next, dur)
        scheduleFile(file, url: next, gen: gen)
    }

    private func scheduleFile(_ file: AVAudioFile, url: URL, gen: Int) {
        player.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack,
                            completionHandler: completion(url: url, gen: gen))
    }

    private func scheduleSegment(_ file: AVAudioFile, url: URL, from frame: AVAudioFramePosition,
                                 count: AVAudioFrameCount, gen: Int) {
        player.scheduleSegment(file, startingFrame: frame, frameCount: count, at: nil,
                               completionCallbackType: .dataPlayedBack,
                               completionHandler: completion(url: url, gen: gen))
    }

    private func completion(url: URL, gen: Int) -> AVAudioPlayerNodeCompletionHandler {
        { [weak self] _ in Task { @MainActor in self?.handleCompletion(url: url, gen: gen) } }
    }

    private func handleCompletion(url: URL, gen: Int) {
        // Guard against superseded schedules (gen) and out-of-order/duplicate
        // callbacks: only the file that is currently `current` advances.
        guard gen == generation, state == .playing, url == current?.url else { return }
        advance()
    }

    private func advance() {
        if let next = scheduledNext {
            // Already rendering seamlessly — just promote it.
            current = next
            currentURL = next.url
            duration = next.duration
            scheduledNext = nil
            setBaseline(seconds: 0)
            onTrackChanged?(next.url)
            scheduleUpcoming(gen: generation)
        } else if let next = upcomingURL {
            // Format boundary / not pre-scheduled: restart (a brief gap here).
            play(url: next)
            onTrackChanged?(next)
        } else {
            state = .stopped
            position = duration
            stopPolling()
            onPlaybackEnded?()
        }
    }

    private func compatible(_ a: AVAudioFormat, _ b: AVAudioFormat) -> Bool {
        a.sampleRate == b.sampleRate && a.channelCount == b.channelCount
    }

    // MARK: - Visualizer audio tap

    func startVisualizerTap() {
        guard !visualizerTapActive else { return }
        visualizerTapActive = true
        let mixer = engine.mainMixerNode
        mixer.removeTap(onBus: 0)
        // The block must NOT be main-actor-isolated — the tap fires on a render
        // thread, so build it in a nonisolated context (else the runtime traps).
        mixer.installTap(onBus: 0, bufferSize: 1024, format: nil, block: Self.tapBlock(visualizerBuffer))
        // The tap only delivers buffers while the engine renders; keep it running
        // so the visualizer stays live even when paused/stopped (renders silence).
        if !engine.isRunning { try? engine.start() }
    }

    nonisolated private static func tapBlock(_ buffer: VisualizerAudioBuffer) -> AVAudioNodeTapBlock {
        { pcm, _ in
            guard let data = pcm.floatChannelData else { return }
            let frames = Int(pcm.frameLength)
            let channels = Int(pcm.format.channelCount)
            var mono = [Float](repeating: 0, count: frames)
            if channels >= 2 {
                let l = data[0], r = data[1]
                for i in 0..<frames { mono[i] = 0.5 * (l[i] + r[i]) }
            } else if channels == 1 {
                let l = data[0]
                for i in 0..<frames { mono[i] = l[i] }
            }
            buffer.write(mono)
        }
    }

    func stopVisualizerTap() {
        guard visualizerTapActive else { return }
        visualizerTapActive = false
        engine.mainMixerNode.removeTap(onBus: 0)
    }

    /// Output route/hardware changed (e.g. headphones unplugged): the engine has
    /// stopped, so rebuild the connection and resume from the current position.
    /// `!engine.isRunning` distinguishes a real route change from our own
    /// reconnects (which keep the engine running).
    private func handleConfigurationChange() {
        guard state == .playing, !engine.isRunning, let cur = current else { return }
        let resumeAt = position
        engine.connect(player, to: engine.mainMixerNode, format: cur.file.processingFormat)
        connectedFormat = cur.file.processingFormat
        seek(to: resumeAt)
    }

    // MARK: - Position

    private func setBaseline(seconds: Double) {
        baseSeconds = seconds
        position = seconds
        if let st = sampleTime() {
            baseSampleTime = st
            pendingBaseSeconds = nil
        } else {
            baseSampleTime = nil
            pendingBaseSeconds = seconds
        }
    }

    private func sampleTime() -> AVAudioFramePosition? {
        guard let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime) else { return nil }
        return playerTime.sampleTime
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.state == .playing else { break }
                self.updatePosition()
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func updatePosition() {
        guard let st = sampleTime() else { return }
        if baseSampleTime == nil, let pending = pendingBaseSeconds {
            baseSampleTime = st
            baseSeconds = pending
            pendingBaseSeconds = nil
        }
        guard let base = baseSampleTime, let sr = current?.file.processingFormat.sampleRate, sr > 0 else { return }
        position = min(max(baseSeconds + Double(st - base) / sr, 0), duration)
    }
}
