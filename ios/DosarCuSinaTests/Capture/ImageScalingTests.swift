import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import DosarCuSina

/// One scaler for every picture: smaller or larger in memory, or read at a size from its file.
/// Sizes, the way up and the callers are pinned here. Placeholder pictures only.
@Suite("Image scaling")
struct ImageScalingTests {

    // MARK: Smaller

    @Test("Smaller: the long edge lands exactly and each side is rounded, never under a pixel",
          arguments: [
            (4032, 3024, 2560, 2560, 1920),
            (3024, 4032, 2400, 1800, 2400),
            (3000, 2001, 2400, 2400, 1601),
            (4031, 3023, 2560, 2560, 1920),
            (10_000, 3, 2560, 2560, 1),
          ])
    func smallerSizes(width: Int, height: Int, longEdge: Int, expectedWidth: Int, expectedHeight: Int) throws {
        let factor = try #require(ImageScaling.factor(width: width, height: height, toLongEdge: longEdge, .down))
        let size = ImageScaling.scaledSize(width: width, height: height, by: factor)
        #expect(size.width == expectedWidth)
        #expect(size.height == expectedHeight)
    }

    @Test("Smaller keeps the picture's proportions and the way it is turned")
    func smallerKeepsTheWayUp() throws {
        let picture = Self.marked(width: 1200, height: 900)
        let smaller = try #require(ImageScaling.scaled(picture, toLongEdge: 400, .down))
        #expect(smaller.width == 400 && smaller.height == 300)
        #expect(Self.isMarked(smaller, x: 2, y: 2), "The corner marked top left stays top left")
        #expect(!Self.isMarked(smaller, x: 397, y: 297))
    }

    // MARK: Larger

    @Test("Larger: up to three times, keeping the way it is turned")
    func larger() throws {
        let small = Self.marked(width: 400, height: 250)
        let threeTimes = try #require(ImageScaling.scaled(small, toLongEdge: 2000, .up))
        #expect(threeTimes.width == 1200 && threeTimes.height == 750, "Never more than three times")
        #expect(Self.isMarked(threeTimes, x: 6, y: 6))
        #expect(!Self.isMarked(threeTimes, x: 1190, y: 740))

        let twice = try #require(ImageScaling.scaled(Self.marked(width: 1000, height: 700), toLongEdge: 2000, .up))
        #expect(twice.width == 2000 && twice.height == 1400)
        #expect(ImageScaling.factor(width: 400, height: 250, toLongEdge: 2000, .up) == ImageScaling.maxEnlargement)
    }

    @Test("A picture that already fits is left as it is, in either direction")
    func alreadyFits() {
        let picture = Self.marked(width: 2000, height: 1000)
        #expect(ImageScaling.scaled(picture, toLongEdge: 2560, .down) === picture)
        #expect(ImageScaling.scaled(picture, toLongEdge: 2000, .down) === picture)
        #expect(ImageScaling.scaled(picture, toLongEdge: 1000, .up) === picture)
        #expect(ImageScaling.scaled(picture, toLongEdge: 2000, .up) === picture)
        #expect(ImageScaling.factor(width: 0, height: 0, toLongEdge: 100, .down) == nil)
        #expect(ImageScaling.factor(width: 100, height: 50, toLongEdge: 0, .up) == nil)
    }

    // MARK: From a file

    @Test("Read from a file: upright whatever the camera wrote, never larger than asked, never enlarged")
    func decoded() throws {
        // Stored sideways with a tag saying to turn it a quarter clockwise, as a phone camera writes it.
        let sideways = try Self.jpeg(Self.marked(width: 300, height: 200), orientation: .right)
        let upright = try #require(ImageScaling.decoded(sideways, maxLongEdge: nil))
        #expect(upright.width == 200 && upright.height == 300)
        #expect(Self.isMarked(upright, x: 195, y: 4), "The stored top left is shown top right")
        #expect(!Self.isMarked(upright, x: 4, y: 4))

        let small = try #require(ImageScaling.decoded(sideways, maxLongEdge: 150))
        #expect(small.width == 100 && small.height == 150)
        let notEnlarged = try #require(ImageScaling.decoded(sideways, maxLongEdge: 4000))
        #expect(notEnlarged.width == 200 && notEnlarged.height == 300)
        #expect(ImageScaling.decoded(Data("not a picture".utf8), maxLongEdge: 100) == nil)
    }

    // MARK: Every caller

    @Test("Kept pages, thumbnails, pages sent to the AI provider and pages read all size through the scaler")
    func callers() throws {
        let sent = try #require(CloudCaptureExtractor.jpeg(Self.marked(width: 3000, height: 2001)))
        let sentPicture = try #require(ImageScaling.decoded(sent, maxLongEdge: nil))
        #expect(sentPicture.width == CloudCaptureExtractor.sentLongEdge && sentPicture.height == 1601)
        #expect(Self.isMarked(sentPicture, x: 4, y: 4))

        let kept = try ImageEncoding.encode(Self.marked(width: 3000, height: 2001), maxLongEdge: CaptureDocumentStore.pageMaxLongEdge, quality: 0.8)
        #expect(kept.width == 2560 && kept.height == 1708)

        let photo = try Self.jpeg(Self.marked(width: 3000, height: 2000), orientation: .right)
        let read = try #require(CaptureInput.image(from: try Self.jpeg(Self.marked(width: 5000, height: 2000), orientation: .up)))
        #expect(max(read.width, read.height) == CaptureInput.maxPixelSize)
        let readUpright = try #require(CaptureInput.image(from: photo))
        #expect(readUpright.width == 2000 && readUpright.height == 3000)

        let inboxPicture = try #require(InboxPreviewer.imageThumbnail(photo))
        #expect(inboxPicture.width == 160 && inboxPicture.height == InboxPreviewer.thumbnailPixels)

        let sectionPhoto = try #require(PhotoPickerRow.keptPhoto(from: photo).flatMap { ImageScaling.decoded($0, maxLongEdge: nil) })
        #expect(sectionPhoto.width == 800 && sectionPhoto.height == PhotoPickerRow.photoLongEdge, "Kept upright, at most 1200")
        #expect(Self.isMarked(sectionPhoto, x: 790, y: 6))
    }

    // MARK: Helpers

    /// A white picture with a red block in its top-left corner, so the way up can be checked.
    static func marked(width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let block = max(4, min(width, height) / 5)
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        // Drawing space starts at the bottom left.
        context.fill(CGRect(x: 0, y: height - block, width: block, height: block))
        return context.makeImage()!
    }

    /// Whether the pixel `x` from the left and `y` from the top is the red mark.
    static func isMarked(_ image: CGImage, x: Int, y: Int) -> Bool {
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            // Move the image so the asked pixel lands on the one-pixel canvas.
            context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        }
        return pixel[0] > 180 && pixel[1] < 90 && pixel[2] < 90
    }

    static func jpeg(_ image: CGImage, orientation: CGImagePropertyOrientation) throws -> Data {
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.9, kCGImagePropertyOrientation: orientation.rawValue]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
