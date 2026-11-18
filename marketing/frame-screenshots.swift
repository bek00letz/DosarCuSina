// Frames the App Store screenshots with their captions, at App Store Connect's exact pixel sizes.
//
//   swift marketing/frame-screenshots.swift <screenshots folder> <output folder> [style…] [--only 01-binder,04-capture]
//
// <screenshots folder> is what scripts/app-store-screenshots.sh wrote: a folder per device with
// "<order>-<scene>-<light|dark>.png". Each picture becomes, for each style, a framed picture of
// the same size (the size App Store Connect asks for that device), in
// <output folder>/<style>/<device>/<order>-<scene>-<appearance>.png. The captions are text, in
// marketing/app-store/captions.json, never in a picture: regenerating is this one command.
//
// The styles (all in SF Pro, the system font, with a real type scale and tight tracking):
//   above  a light background, the caption above, the device in a thin bezel running off the bottom
//   night  the icon's night blue, a white caption, the whole device in its bezel
//   bleed  the app's blue, a white caption, the screen without a bezel, running off the bottom
import AppKit
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Caption: Decodable {
    let title: String
    let subtitle: String?
}

/// sRGB from a hex number.
func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

struct Style {
    let name: String
    /// The background's top and bottom colours.
    let background: (CGColor, CGColor)
    let title: CGColor
    let subtitle: CGColor
    /// The device's width as a share of the canvas's.
    let deviceWidth: CGFloat
    /// Whether the device has a bezel around its screen.
    let bezel: Bool
    /// Whether the device runs off the bottom edge (else it stands whole, centred under the caption).
    let bleedsOffBottom: Bool

    static let all: [Style] = [
        Style(name: "above", background: (color(0xF7F8FB), color(0xE4E9F2)), title: color(0x0B1220), subtitle: color(0x4A5568),
              deviceWidth: 0.80, bezel: true, bleedsOffBottom: true),
        Style(name: "night", background: (color(0x1C2B52), color(0x0A0F1E)), title: color(0xFFFFFF), subtitle: color(0xB8C4DE),
              deviceWidth: 0.70, bezel: true, bleedsOffBottom: false),
        Style(name: "bleed", background: (color(0x1E7BFF), color(0x0A5BD8)), title: color(0xFFFFFF), subtitle: color(0xDCE9FF),
              deviceWidth: 0.86, bezel: false, bleedsOffBottom: true),
    ]
}

func loadImage(_ url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

func writePNG(_ image: CGImage, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

/// A caption's lines, laid out centred in `width`; returns the height they take.
func drawText(_ string: String, size: CGFloat, weight: NSFont.Weight, color: CGColor, tracking: CGFloat,
              lineHeight: CGFloat, in context: CGContext, top: CGFloat, left: CGFloat, width: CGFloat, canvasHeight: CGFloat) -> CGFloat {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineBreakMode = .byWordWrapping
    paragraph.minimumLineHeight = size * lineHeight
    paragraph.maximumLineHeight = size * lineHeight
    // No widow: the last two words stay together.
    var text = string
    if let last = text.range(of: " ", options: .backwards) { text.replaceSubrange(last, with: "\u{00A0}") }
    let attributed = NSAttributedString(string: text, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor(cgColor: color) ?? .black,
        .kern: size * tracking,
        .paragraphStyle: paragraph,
    ])
    let framesetter = CTFramesetterCreateWithAttributedString(attributed)
    let fit = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(), nil, CGSize(width: width, height: .greatestFiniteMagnitude), nil)
    let height = ceil(fit.height)
    let path = CGPath(rect: CGRect(x: left, y: canvasHeight - top - height, width: width, height: height), transform: nil)
    let frame = CTFramesetterCreateFrame(framesetter, CFRange(), path, nil)
    CTFrameDraw(frame, context)
    return height
}

func frame(_ screen: CGImage, caption: Caption, style: Style) -> CGImage? {
    let width = CGFloat(screen.width), height = CGFloat(screen.height)
    let isPad = width / height > 0.6
    guard let context = CGContext(data: nil, width: screen.width, height: screen.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
    // Background: a quiet vertical gradient.
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [style.background.0, style.background.1] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height), end: CGPoint(x: 0, y: 0), options: [])

    // The caption: one type scale for every size, from the canvas's width.
    let unit = isPad ? width / 1.55 : width
    let margin = width * 0.08
    let titleSize = (unit * 0.074).rounded()
    let subtitleSize = (unit * 0.040).rounded()
    var top = height * (isPad ? 0.055 : 0.065)
    top += drawText(caption.title, size: titleSize, weight: .bold, color: style.title, tracking: -0.008, lineHeight: 1.08,
                    in: context, top: top, left: margin, width: width - margin * 2, canvasHeight: height)
    if let subtitle = caption.subtitle {
        top += subtitleSize * 0.55
        top += drawText(subtitle, size: subtitleSize, weight: .regular, color: style.subtitle, tracking: 0, lineHeight: 1.2,
                        in: context, top: top, left: margin, width: width - margin * 2, canvasHeight: height)
    }
    top += height * 0.04

    // The device: the screen, its corners concentric with the bezel's.
    let deviceWidth = width * style.deviceWidth
    let scale = deviceWidth / width
    let screenSize = CGSize(width: width * scale, height: height * scale)
    let screenRadius = (isPad ? 0.026 : 0.125) * screenSize.width
    let bezelWidth = style.bezel ? screenSize.width * (isPad ? 0.022 : 0.032) : 0
    let outer = CGSize(width: screenSize.width + bezelWidth * 2, height: screenSize.height + bezelWidth * 2)
    let available = height - top
    let deviceTop = top
    var fit: CGFloat = 1
    if !style.bleedsOffBottom, outer.height > available - height * 0.04 { fit = (available - height * 0.04) / outer.height }
    let outerRect = CGRect(x: (width - outer.width * fit) / 2, y: height - deviceTop - outer.height * fit, width: outer.width * fit, height: outer.height * fit)
    let screenRect = outerRect.insetBy(dx: bezelWidth * fit, dy: bezelWidth * fit)

    // A soft, layered shadow under the device.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -width * 0.012), blur: width * 0.05, color: color(0x000000, alpha: 0.28))
    let outerPath = CGPath(roundedRect: outerRect, cornerWidth: screenRadius * fit + bezelWidth * fit, cornerHeight: screenRadius * fit + bezelWidth * fit, transform: nil)
    context.addPath(outerPath)
    context.setFillColor(style.bezel ? color(0x101114) : color(0xFFFFFF))
    context.fillPath()
    context.restoreGState()
    if style.bezel {
        // A hairline on the bezel's edge, as light catches the frame.
        context.addPath(CGPath(roundedRect: outerRect.insetBy(dx: 1.5, dy: 1.5), cornerWidth: screenRadius * fit + bezelWidth * fit - 1.5,
                               cornerHeight: screenRadius * fit + bezelWidth * fit - 1.5, transform: nil))
        context.setStrokeColor(color(0x5A5F6B, alpha: 0.9))
        context.setLineWidth(3)
        context.strokePath()
    }
    context.saveGState()
    context.addPath(CGPath(roundedRect: screenRect, cornerWidth: screenRadius * fit, cornerHeight: screenRadius * fit, transform: nil))
    context.clip()
    context.interpolationQuality = .high
    context.draw(screen, in: screenRect)
    context.restoreGState()
    return context.makeImage()
}

// MARK: Main

var arguments = Array(CommandLine.arguments.dropFirst())
var only: Set<String>?
if let index = arguments.firstIndex(of: "--only"), arguments.indices.contains(index + 1) {
    only = Set(arguments[index + 1].split(separator: ",").map(String.init))
    arguments.removeSubrange(index...index + 1)
}
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("Usage: swift marketing/frame-screenshots.swift <screenshots folder> <output folder> [style…] [--only 01-binder,…]\n".utf8))
    exit(2)
}
let input = URL(fileURLWithPath: arguments[0]), output = URL(fileURLWithPath: arguments[1])
let wantedStyles = Set(arguments.dropFirst(2))
let styles = wantedStyles.isEmpty ? Style.all : Style.all.filter { wantedStyles.contains($0.name) }
let captionsURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "app-store/captions.json")
let captions = try JSONDecoder().decode([String: [String: Caption]].self, from: Data(contentsOf: captionsURL))["ro"] ?? [:]

let files = FileManager.default
var written = 0
for device in try files.contentsOfDirectory(at: input, includingPropertiesForKeys: [.isDirectoryKey]).sorted(by: { $0.path < $1.path })
where (try? device.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
    for file in try files.contentsOfDirectory(at: device, includingPropertiesForKeys: nil).sorted(by: { $0.path < $1.path })
    where file.pathExtension == "png" {
        let name = file.deletingPathExtension().lastPathComponent
        let scene = name.split(separator: "-").prefix(2).joined(separator: "-")
        guard only?.contains(scene) ?? true else { continue }
        guard let caption = captions[scene] else { print("No caption for \(scene); left out."); continue }
        guard let screen = loadImage(file) else { print("Can't read \(file.path)."); continue }
        for style in styles {
            guard let framed = frame(screen, caption: caption, style: style) else { continue }
            try writePNG(framed, to: output.appending(path: "\(style.name)/\(device.lastPathComponent)/\(name).png"))
            written += 1
        }
    }
}
print("Framed \(written) screenshots into \(output.path)")
