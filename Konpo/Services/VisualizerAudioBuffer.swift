import Foundation

/// Thread-safe hand-off of recent audio samples from the render thread (where the
/// engine tap fires) to the main thread (where they're pushed to the visualizer).
/// A brief lock is fine here — the visualizer is not sample-accurate.
final class VisualizerAudioBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private let cap = 8192

    func write(_ chunk: [Float]) {
        lock.lock()
        samples.append(contentsOf: chunk)
        if samples.count > cap { samples.removeFirst(samples.count - cap) }
        lock.unlock()
    }

    /// Returns and clears the accumulated samples.
    func drain() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        let out = samples
        samples.removeAll(keepingCapacity: true)
        return out
    }
}
