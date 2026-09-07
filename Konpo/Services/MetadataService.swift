import Foundation
import AVFoundation
import AudioToolbox
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

/// Tag/format/artwork read off a single audio file. Value type so it crosses the
/// actor boundary safely.
struct TrackMetadata: Sendable {
    var title: String?
    var artist: String?
    var album: String?
    var trackNumber: Int?
    var year: String?
    var durationSeconds: Double?
    var codec: String?
    var sampleRate: Double?
    var bitDepth: Int?
    var channels: Int?
}

/// Loads and caches track metadata and downscaled artwork off the main actor.
actor MetadataService {
    /// Tag/format data is small, so this budget is effectively an entry count.
    private var metaCache = LRUCache<URL, TrackMetadata>(costLimit: 20_000)
    /// Resolved artwork keyed by track URL *and* requested size; empty Data
    /// caches a "no artwork" result. Keying by size matters — the panel (small)
    /// and the full-size window (large) must not share one downscaled copy.
    ///
    /// Budgeted in bytes: this holds encoded JPEG data, including 2048px art from
    /// the full-size window, so scrolling a large library through the album grid
    /// would otherwise grow the process without bound.
    private var artCache = LRUCache<String, Data>(costLimit: 96 * 1024 * 1024)

    /// Loads already running, so concurrent requests for the same key share one
    /// decode instead of each doing the full work. Without this the actor frees
    /// itself at the first `await`, so a cache miss is not exclusive — the album
    /// grid cell and the art panel asking for the same cover is exactly that case.
    private var metaTasks: [URL: Task<TrackMetadata, Never>] = [:]
    private var artTasks: [String: Task<Data?, Never>] = [:]

    // MARK: - Public API

    func metadata(for url: URL) async -> TrackMetadata {
        if let cached = metaCache[url] { return cached }
        if let inFlight = metaTasks[url] { return await inFlight.value }

        let task = Task { await Self.loadMetadata(url: url) }
        metaTasks[url] = task
        let meta = await task.value
        metaTasks[url] = nil
        metaCache.set(meta, forKey: url)
        return meta
    }

    /// Drop all cached metadata/artwork so a refresh re-reads from disk.
    func clearCache() {
        metaCache.removeAll()
        artCache.removeAll()
    }

    /// Downscaled JPEG data for the track's artwork: embedded first, then a
    /// cover/folder image in the same directory. Returns nil when none found.
    func artworkData(for url: URL, maxPixel: Int) async -> Data? {
        let key = "\(maxPixel):\(url.absoluteString)"
        return await artwork(key: key) {
            await Self.loadArtwork(url: url, maxPixel: maxPixel)
        }
    }

    /// Downscaled artwork for an album cell. Looks in the album *folder* first —
    /// a multi-disc album's cover.jpg sits beside CD1/CD2, not inside them — then
    /// falls back to a representative track's embedded artwork. Cached per album
    /// folder and size, separate from the per-track cache.
    func albumArtworkData(folder: URL, track: URL?, maxPixel: Int) async -> Data? {
        let key = "album:\(maxPixel):\(folder.absoluteString)"
        return await artwork(key: key) {
            await Self.loadAlbumArtwork(folder: folder, track: track, maxPixel: maxPixel)
        }
    }

    /// Shared cache / in-flight / store path for both artwork lookups.
    private func artwork(key: String, load: @escaping @Sendable () async -> Data?) async -> Data? {
        if let cached = artCache[key] { return cached.isEmpty ? nil : cached }
        if let inFlight = artTasks[key] { return await inFlight.value }

        let task = Task { await load() }
        artTasks[key] = task
        let resolved = await task.value
        artTasks[key] = nil
        // An empty Data is the "no artwork here" sentinel and costs nothing to keep.
        artCache.set(resolved ?? Data(), forKey: key, cost: resolved?.count ?? 1)
        return resolved
    }

    // MARK: - Metadata loading (nonisolated: pure, runs on the caller's task)

    private nonisolated static func loadMetadata(url: URL) async -> TrackMetadata {
        var m = TrackMetadata()

        // Format details (codec/sample rate/bit depth/channels/duration) come
        // cheaply from the file's stream description.
        if let file = try? AVAudioFile(forReading: url) {
            let asbd = file.fileFormat.streamDescription.pointee
            m.codec = codecName(asbd.mFormatID)
            m.bitDepth = bitDepth(asbd)
            m.sampleRate = file.fileFormat.sampleRate
            m.channels = Int(file.fileFormat.channelCount)
            let sr = file.processingFormat.sampleRate
            if sr > 0 { m.durationSeconds = Double(file.length) / sr }
        }

        // Tags via AVURLAsset common/keyspace metadata.
        let asset = AVURLAsset(url: url)
        if m.durationSeconds == nil, let d = try? await asset.load(.duration) {
            let secs = CMTimeGetSeconds(d)
            if secs.isFinite { m.durationSeconds = secs }
        }
        guard let items = try? await asset.load(.metadata) else { return m }
        for item in items {
            if let key = item.commonKey {
                switch key {
                case .commonKeyTitle:
                    if let s = try? await item.load(.stringValue) { m.title = s }
                case .commonKeyArtist:
                    if let s = try? await item.load(.stringValue) { m.artist = s }
                case .commonKeyAlbumName:
                    if let s = try? await item.load(.stringValue) { m.album = s }
                case .commonKeyCreationDate:
                    if let s = try? await item.load(.stringValue) { m.year = year(from: s) }
                default:
                    break
                }
            }
            switch item.identifier {
            case .some(.iTunesMetadataTrackNumber):
                // Copy to an Array before indexing: Data subscripts by absolute
                // index, so a slice with a non-zero startIndex would trap here
                // rather than merely read the wrong bytes.
                if let data = try? await item.load(.dataValue), data.count >= 4 {
                    let bytes = Array(data)
                    m.trackNumber = Int(bytes[2]) << 8 | Int(bytes[3])
                } else if let n = try? await item.load(.numberValue) {
                    m.trackNumber = n.intValue
                }
            case .some(.id3MetadataTrackNumber):
                if let s = try? await item.load(.stringValue),
                   let first = s.split(separator: "/").first, let n = Int(first) {
                    m.trackNumber = n
                }
            default:
                break
            }

            // Year fallback: any date-ish atom (iTunes ©day, ID3 year, etc.),
            // matched by identifier/key since the exact mapping varies by format.
            if m.year == nil {
                let idStr = item.identifier?.rawValue.lowercased() ?? ""
                let keyStr = (item.key as? String)?.lowercased() ?? ""
                if ["day", "year", "date"].contains(where: { idStr.contains($0) || keyStr.contains($0) }) {
                    if let s = try? await item.load(.stringValue) {
                        m.year = year(from: s)
                    } else if let n = try? await item.load(.numberValue) {
                        m.year = year(from: n.stringValue)
                    }
                }
            }
        }
        return m
    }

    // MARK: - Artwork loading

    /// Resolve the best artwork source, then downscale. A cover/folder image is
    /// often far higher-resolution than the thumbnail baked into the audio file,
    /// so pick whichever source has the larger pixel dimensions rather than
    /// always preferring the embedded one.
    private nonisolated static func loadArtwork(url: URL, maxPixel: Int) async -> Data? {
        let embedded = await embeddedArtwork(url: url)
        let folderURL = folderArtworkURL(in: url.deletingLastPathComponent())

        let embeddedDim = pixelDimension(data: embedded)
        let folderDim = folderURL.map { pixelDimension(url: $0) } ?? 0

        if folderDim > embeddedDim, let folderURL, let data = try? Data(contentsOf: folderURL) {
            return downscale(data, maxPixel: maxPixel)
        }
        if let embedded { return downscale(embedded, maxPixel: maxPixel) }
        if let folderURL, let data = try? Data(contentsOf: folderURL) {
            return downscale(data, maxPixel: maxPixel)
        }
        return nil
    }

    /// Album-cell artwork: the album folder's own cover image wins (it's shared
    /// by multi-disc albums), otherwise defer to the representative track's
    /// embedded/folder artwork.
    private nonisolated static func loadAlbumArtwork(folder: URL, track: URL?, maxPixel: Int) async -> Data? {
        if let coverURL = folderArtworkURL(in: folder), let data = try? Data(contentsOf: coverURL) {
            return downscale(data, maxPixel: maxPixel)
        }
        if let track { return await loadArtwork(url: track, maxPixel: maxPixel) }
        return nil
    }

    private nonisolated static func embeddedArtwork(url: URL) async -> Data? {
        let asset = AVURLAsset(url: url)
        guard let items = try? await asset.load(.metadata) else { return nil }
        for item in items where item.commonKey == .commonKeyArtwork {
            if let data = try? await item.load(.dataValue) { return data }
        }
        return nil
    }

    private nonisolated static func folderArtworkURL(in folder: URL) -> URL? {
        let names: Set<String> = ["cover", "folder", "front", "album", "artwork", "albumart"]
        let exts: Set<String> = ["jpg", "jpeg", "png", "webp", "gif"]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        for entry in entries {
            let base = entry.deletingPathExtension().lastPathComponent.lowercased()
            if exts.contains(entry.pathExtension.lowercased()), names.contains(base) {
                return entry
            }
        }
        return nil
    }

    /// Longest-edge pixel size of an image, read from its header (no full decode).
    private nonisolated static func pixelDimension(data: Data?) -> Int {
        guard let data, let src = CGImageSourceCreateWithData(data as CFData, nil) else { return 0 }
        return pixelDimension(source: src)
    }
    private nonisolated static func pixelDimension(url: URL) -> Int {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return 0 }
        return pixelDimension(source: src)
    }
    private nonisolated static func pixelDimension(source: CGImageSource) -> Int {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return 0 }
        let w = (props[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let h = (props[kCGImagePropertyPixelHeight] as? Int) ?? 0
        return max(w, h)
    }

    /// Downscale to `maxPixel` on the long edge so a giant cover never reaches
    /// SwiftUI. If the image already fits, the original bytes are returned
    /// untouched — re-encoding a small cover only adds JPEG artifacts and blur
    /// (which is exactly what made a 600px folder.jpg look worse than the file).
    /// When a resize is genuinely needed, re-encode at high quality.
    private nonisolated static func downscale(_ data: Data, maxPixel: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return data }
        if pixelDimension(source: source) <= maxPixel { return data }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return data }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return data }
        let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.92]
        CGImageDestinationAddImage(dest, thumb, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return data }
        return out as Data
    }

    // MARK: - Format helpers

    private nonisolated static func codecName(_ id: AudioFormatID) -> String {
        switch id {
        case kAudioFormatAppleLossless: return "ALAC"
        case kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2: return "AAC"
        case kAudioFormatMPEGLayer3: return "MP3"
        case kAudioFormatLinearPCM: return "PCM"
        case kAudioFormatFLAC: return "FLAC"
        default: return fourCharString(id)
        }
    }

    private nonisolated static func bitDepth(_ asbd: AudioStreamBasicDescription) -> Int? {
        if asbd.mBitsPerChannel > 0 { return Int(asbd.mBitsPerChannel) }
        if asbd.mFormatID == kAudioFormatAppleLossless {
            switch asbd.mFormatFlags {
            case kAppleLosslessFormatFlag_16BitSourceData: return 16
            case kAppleLosslessFormatFlag_20BitSourceData: return 20
            case kAppleLosslessFormatFlag_24BitSourceData: return 24
            case kAppleLosslessFormatFlag_32BitSourceData: return 32
            default: return nil
            }
        }
        return nil
    }

    private nonisolated static func fourCharString(_ id: AudioFormatID) -> String {
        let bytes = [UInt8((id >> 24) & 0xff), UInt8((id >> 16) & 0xff),
                     UInt8((id >> 8) & 0xff), UInt8(id & 0xff)]
        let s = String(bytes: bytes, encoding: .macOSRoman) ?? ""
        return s.trimmingCharacters(in: .whitespaces).uppercased()
    }

    private nonisolated static func year(from dateString: String) -> String? {
        let digits = dateString.prefix(4)
        return digits.count == 4 && digits.allSatisfy(\.isNumber) ? String(digits) : nil
    }
}
