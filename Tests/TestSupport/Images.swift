import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A PNG of one flat color, `width` × `height` pixels, as a copied image would be.
public func flatPNG(width: Int, height: Int) throws -> Data {
    struct CouldNotDraw: Error {}
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw CouldNotDraw() }
    context.setFillColor(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let data = NSMutableData()
    guard let image = context.makeImage(),
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
    else { throw CouldNotDraw() }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CouldNotDraw() }
    return data as Data
}
