import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A copied image's thumbnails, rendered once when it's stored, at the exact pixel sizes the panel draws them
/// (`docs/BRIEF-CLIPBOARD.md` §5). ImageIO decodes straight to the thumbnail's size, never the full image.
enum ImageThumbnails {
    struct Rendered {
        /// The image's size in pixels, upright.
        let width: Int
        let height: Int
        /// PNG, `rowPixels` square: the image filled and cropped to the square.
        let row: Data
        /// PNG, fitted into the preview box, never larger than the image itself.
        let preview: Data
    }

    /// Nil when `data` isn't an image ImageIO can read.
    static func render(_ data: Data, rowPixels: Int, preview box: (width: Int, height: Int)) -> Rendered? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            var width = properties[kCGImagePropertyPixelWidth] as? Int,
            var height = properties[kCGImagePropertyPixelHeight] as? Int,
            width > 0, height > 0
        else { return nil }
        // Orientations 5–8 turn the image a quarter, so the upright image is the other way around.
        if let orientation = properties[kCGImagePropertyOrientation] as? UInt32, orientation >= 5 {
            swap(&width, &height)
        }
        let longest = Double(max(width, height))

        let fit = min(1, Double(box.width) / Double(width), Double(box.height) / Double(height))
        let fill = Double(rowPixels) / Double(min(width, height))
        guard let preview = thumbnail(source, maxPixels: longest * fit).flatMap({ png($0) }),
            let rowImage = thumbnail(source, maxPixels: min(longest, longest * fill)),
            let row = square(rowImage, pixels: rowPixels).flatMap({ png($0) })
        else { return nil }
        return Rendered(width: width, height: height, row: row, preview: preview)
    }

    /// The image, upright, scaled so its longer side is `maxPixels` (never larger than it is).
    private static func thumbnail(_ source: CGImageSource, maxPixels: Double) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(maxPixels.rounded())),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// `image` filling a `pixels` square, centered and cropped; smaller images are scaled up to fill it.
    private static func square(_ image: CGImage, pixels: Int) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let side = Double(pixels)
        let scale = max(side / Double(image.width), side / Double(image.height))
        let size = CGSize(width: Double(image.width) * scale, height: Double(image.height) * scale)
        context.interpolationQuality = .high
        context.draw(
            image,
            in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2, width: size.width, height: size.height))
        return context.makeImage()
    }

    static func png(_ image: CGImage, properties: [CFString: Any] = [:]) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
