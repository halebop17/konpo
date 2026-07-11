import Foundation
import MediaPlayer
import AppKit

/// Bridges to macOS media keys, Control Center, and the Now Playing widget via
/// MPRemoteCommandCenter (input) and MPNowPlayingInfoCenter (output).
@MainActor
final class NowPlayingService {
    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onToggle: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onSeek: ((Double) -> Void)?

    init() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.onPlay?() }; return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.onPause?() }; return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.onToggle?() }; return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.onNext?() }; return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.onPrevious?() }; return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            MainActor.assumeIsolated { self?.onSeek?(event.positionTime) }
            return .success
        }
    }

    func update(title: String?, artist: String?, album: String?,
                duration: Double, elapsed: Double, isPlaying: Bool, artwork: NSImage?) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title ?? "",
            MPMediaItemPropertyArtist: artist ?? "",
            MPMediaItemPropertyAlbumTitle: album ?? "",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let artwork {
            info[MPMediaItemPropertyArtwork] = Self.makeArtwork(artwork)
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    /// MediaPlayer invokes the artwork request handler on a background queue, so
    /// it must NOT be main-actor-isolated (else the runtime traps). Building it
    /// in a nonisolated context strips the isolation.
    nonisolated private static func makeArtwork(_ image: NSImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
