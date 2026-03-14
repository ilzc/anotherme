import Foundation
import ScreenCaptureKit
import CoreGraphics

final class ScreenProvider {

    /// Get all available displays
    func availableDisplays() async throws -> [SCDisplay] {
        let content = try await SCShareableContent.current
        return content.displays
    }

    /// Capture a single screenshot of the specified display
    func captureScreen(display: SCDisplay) async throws -> CGImage {
        let filter = SCContentFilter(display: display, excludingWindows: [])

        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
        return image
    }

    /// Compress CGImage to JPEG base64 string
    static func imageToBase64(
        _ image: CGImage,
        quality: CGFloat = 0.7,
        maxWidth: Int = 1920
    ) -> String? {
        // Resize if needed
        let targetImage: CGImage
        if image.width > maxWidth {
            let scale = CGFloat(maxWidth) / CGFloat(image.width)
            let newWidth = Int(CGFloat(image.width) * scale)
            let newHeight = Int(CGFloat(image.height) * scale)

            guard let context = CGContext(
                data: nil,
                width: newWidth,
                height: newHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
            ) else {
                print("[ScreenProvider] Failed to create CGContext for resize (\(newWidth)x\(newHeight))")
                return nil
            }

            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))

            guard let resized = context.makeImage() else {
                print("[ScreenProvider] CGContext.makeImage() returned nil after resize")
                return nil
            }
            targetImage = resized
        } else {
            targetImage = image
        }

        // Convert to JPEG data
        let bitmapRep = NSBitmapImageRep(cgImage: targetImage)
        guard let jpegData = bitmapRep.representation(
            using: .jpeg,
            properties: [.compressionFactor: quality]
        ) else {
            print("[ScreenProvider] NSBitmapImageRep.representation() returned nil (JPEG conversion failed for \(targetImage.width)x\(targetImage.height) image)")
            return nil
        }

        return jpegData.base64EncodedString()
    }
}

import AppKit
