import CoreGraphics

/// Pixel-level deduplication for screen captures.
/// Compares consecutive frames as 32×32 grayscale thumbnails to skip unchanged screens.
///
/// Thread safety: This class is **not** Sendable. It is designed to be used from a single
/// isolation context (e.g. the `@MainActor`-isolated `CaptureService`), which owns one
/// instance and calls `hasChanged(_:)` sequentially within the capture pipeline.
final class ImageDeduplicator {

    /// Grayscale pixel buffer of the previous frame's thumbnail (32×32 = 1024 bytes).
    private var lastThumbnail: [UInt8]?

    private static let thumbnailSize = 32
    private static let pixelCount = thumbnailSize * thumbnailSize  // 1024

    // MARK: - Thumbnail Generation

    /// Scales the given image down to a 32×32 grayscale bitmap and returns the raw pixel buffer.
    ///
    /// - Parameter image: A full-resolution `CGImage` captured from the screen.
    /// - Returns: A 1024-element `[UInt8]` array representing 32×32 grayscale pixel values.
    static func makeThumbnail(from image: CGImage) -> [UInt8] {
        let size = thumbnailSize
        var pixels = [UInt8](repeating: 0, count: pixelCount)
        let colorSpace = CGColorSpaceCreateDeviceGray()

        guard let ctx = CGContext(
            data: &pixels,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size,
            space: colorSpace,
            bitmapInfo: 0
        ) else {
            return pixels
        }

        ctx.interpolationQuality = .low  // Fast & deterministic for dedup comparison
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        return pixels
    }

    // MARK: - Change Detection

    /// Determines whether the current frame differs enough from the previous frame to warrant analysis.
    ///
    /// The first call always returns `true` (no previous frame to compare against).
    /// Subsequent calls compare 32×32 grayscale thumbnails: pixels whose absolute difference
    /// exceeds `pixelTolerance` are counted as "changed". If the ratio of changed pixels
    /// to total pixels meets or exceeds `threshold`, the frame is considered changed.
    ///
    /// - Parameters:
    ///   - image: The newly captured screen image.
    ///   - threshold: Fraction of pixels that must differ to consider the frame changed (default 5%).
    ///   - pixelTolerance: Minimum per-pixel brightness difference to count as changed (default 10).
    /// - Returns: `true` if the content has changed and should be analyzed; `false` to skip.
    func hasChanged(_ image: CGImage, threshold: Double = 0.05, pixelTolerance: UInt8 = 10) -> Bool {
        let current = Self.makeThumbnail(from: image)
        defer { lastThumbnail = current }

        guard let previous = lastThumbnail else {
            return true  // First frame — no previous data to compare
        }

        var diffCount = 0
        let tolerance = Int(pixelTolerance)

        for i in 0..<Self.pixelCount {
            if abs(Int(current[i]) - Int(previous[i])) > tolerance {
                diffCount += 1
            }
        }

        return Double(diffCount) / Double(Self.pixelCount) >= threshold
    }
}
