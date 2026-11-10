import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO

/// The one way a picture changes size: in memory (`scaled`, smaller or larger) or while it
/// is read from its file (`decoded`, upright). Every page kept, thumbnail, hero photo, page
/// read and page sent to the AI provider is sized here. Flattening a photographed page
/// lives here too, with the shared Core Image context, and the one bitmap canvas (`canvas`)
/// every picture is drawn on. Turning is `DocumentPicture.turned`, on that canvas.
enum ImageScaling {

    /// Which way `scaled` may change a picture's size.
    enum Direction: Sendable {
        /// Only smaller: a page kept, a thumbnail, a page sent to the AI provider.
        case down
        /// Only larger, at most `maxEnlargement` times: small print made big enough to read.
        case up
    }

    /// The most a picture is enlarged: beyond it, enlarging adds blur, not detail.
    static let maxEnlargement: Double = 3

    /// The picture with its long edge brought to `longEdge`, keeping its proportions and the
    /// way it is turned, changed only in the direction allowed. The picture itself when it
    /// already fits; nil only when it couldn't be drawn.
    ///
    /// Smaller is drawn with high-quality interpolation into an sRGB canvas, each side rounded
    /// to the nearest pixel; larger with a Lanczos filter.
    static func scaled(_ image: CGImage, toLongEdge longEdge: Int, _ direction: Direction) -> CGImage? {
        guard let factor = factor(width: image.width, height: image.height, toLongEdge: longEdge, direction) else { return image }
        switch direction {
        case .down:
            let size = scaledSize(width: image.width, height: image.height, by: factor)
            return redrawn(image, width: size.width, height: size.height)
        case .up:
            let filter = CIFilter.lanczosScaleTransform()
            filter.inputImage = CIImage(cgImage: image)
            filter.scale = Float(factor)
            filter.aspectRatio = 1
            return filter.outputImage.flatMap(render)
        }
    }

    /// How much `scaled` changes a picture of this size, or nil when it is left as it is.
    static func factor(width: Int, height: Int, toLongEdge longEdge: Int, _ direction: Direction) -> Double? {
        let current = max(width, height)
        guard current > 0, longEdge > 0 else { return nil }
        switch direction {
        case .down:
            guard current > longEdge else { return nil }
            return Double(longEdge) / Double(current)
        case .up:
            guard current < longEdge else { return nil }
            return min(Double(longEdge) / Double(current), maxEnlargement)
        }
    }

    /// The pixel size a picture made smaller by `factor` is drawn at: each side rounded, never under one pixel.
    static func scaledSize(width: Int, height: Int, by factor: Double) -> (width: Int, height: Int) {
        (max(1, Int((Double(width) * factor).rounded())), max(1, Int((Double(height) * factor).rounded())))
    }

    /// An encoded picture (JPEG, HEIC, PNG) read upright, its long edge at most `maxLongEdge`
    /// (as stored when nil). Read at that size from the file, so a large photo is never decoded whole
    /// to be made small. Never enlarged.
    static func decoded(_ data: Data, maxLongEdge: Int?) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        if let maxLongEdge { options[kCGImageSourceThumbnailMaxPixelSize] = maxLongEdge }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The quadrilateral (top-left, top-right, bottom-right, bottom-left, image space) made rectangular.
    static func flattened(_ image: CGImage, corners: [CGPoint]) -> CGImage? {
        guard corners.count == 4 else { return nil }
        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = CIImage(cgImage: image)
        filter.topLeft = corners[0]
        filter.topRight = corners[1]
        filter.bottomRight = corners[2]
        filter.bottomLeft = corners[3]
        return filter.outputImage.flatMap(render)
    }

    // MARK: Drawing

    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// The one bitmap canvas a picture is drawn on, here and by `DocumentPicture` (a page
    /// turned, a PDF page drawn): `width` × `height` pixels, sRGB, eight bits a channel, no
    /// alpha. Painted white first when `onWhite`, so what isn't drawn on reads as paper.
    static func canvas(width: Int, height: Int, onWhite: Bool) -> CGContext? {
        guard width > 0, height > 0, let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        if onWhite {
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return context
    }

    private static func redrawn(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard let context = canvas(width: width, height: height, onWhite: false) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private static func render(_ image: CIImage) -> CGImage? {
        let extent = image.extent.integral
        guard extent.width > 0, extent.height > 0 else { return nil }
        return context.createCGImage(image, from: extent)
    }
}
