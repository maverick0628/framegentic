import Foundation
import CoreGraphics

// A plain actor, not @MainActor: this type does JPEG encoding and file I/O.
// Nothing calls it yet, but the capture loop (a later task) will push every
// captured frame through here at a sub-second interval, and this app is a
// menu bar app whose scrubber UI can't afford to contend with that on the
// main thread. Actor isolation still serialises access to tempFileManager
// (closing the same race @MainActor would have), just without pinning the
// work to a specific thread.
public actor OptimizationPipeline {
    private let tempFileManager = TempFileManager()

    public init() {}

    // Pure and stateless (unlike the rest of this type), so it stays callable
    // without hopping onto the actor.
    public nonisolated static func dedup(_ frames: [CapturedFrame], threshold: Double) -> [CapturedFrame] {
        guard frames.count > 2 else { return frames }

        let hashes = frames.map { DHash.hash($0.image) }
        var keep = [Bool](repeating: false, count: frames.count)
        keep[0] = true
        keep[frames.count - 1] = true

        for i in 1..<(frames.count - 1) {
            if !DHash.areSimilar(hashes[i - 1], hashes[i], threshold: threshold) {
                keep[i] = true
            }
        }

        return zip(frames, keep).compactMap { $0.1 ? $0.0 : nil }
    }

    public func process(
        frames: [CapturedFrame],
        maxWidth: Int = 1024,
        jpegQuality: CGFloat = 0.75,
        dedupThreshold: Double = 0.9
    ) async -> [URL] {
        let deduped = Self.dedup(frames, threshold: dedupThreshold)
        var urls: [URL] = []

        for (index, frame) in deduped.enumerated() {
            let downsampled = ImageProcessor.downsample(frame.image, maxWidth: maxWidth)
            guard let jpegData = ImageProcessor.encodeJPEG(downsampled, quality: jpegQuality) else { continue }
            let filename = String(format: "frame-%03d.jpg", index)
            guard let url = try? await tempFileManager.write(jpegData, filename: filename) else { continue }
            urls.append(url)
        }

        return urls
    }

    public func processAndCopy(
        frames: [CapturedFrame],
        maxWidth: Int = 1024,
        jpegQuality: CGFloat = 0.75,
        dedupThreshold: Double = 0.9,
        ttl: TimeInterval = 300
    ) async -> Int {
        let urls = await process(frames: frames, maxWidth: maxWidth, jpegQuality: jpegQuality, dedupThreshold: dedupThreshold)
        guard !urls.isEmpty else { return 0 }
        ClipboardWriter.writeFileURLs(urls)
        await tempFileManager.scheduleCleanup(after: ttl)
        return urls.count
    }

    public func cleanup() async {
        await tempFileManager.cleanupAll()
    }
}
