// Draws the App Store's product page header and search-results artwork, at App Store Connect's
// exact pixel sizes, with no words in them (nothing to translate).
//
//   swift marketing/header-art.swift <output folder>
//
// Writes <output folder>/header-3840x1646.png (21:9, the product page's header) and
// <output folder>/search-3840x2560.png (3:2, a search result). Both are PNGs without an alpha
// channel, in sRGB.
//
// The art is the app icon's ring binder, larger, on the icon's deep navy, with a few papers fanned
// around it: a passport, a bill, an insurance policy, a home, a pet's card, a deadline. Every paper
// is placeholder shapes only, never a real document. Apple crops the header's sides on some devices
// and asks for the key artwork inside a centred safe area (header: 1646 × 661 at x 1097, y 493;
// search: 2168 × 1030 at x 836, y 765), so the binder sits inside it and the papers may be cut.
import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// sRGB from a hex number.
func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

// MARK: - Shapes

/// A rectangle with continuous corners (the curve starts further out and eases in, as Apple's do).
func continuousRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    let r = min(radius, rect.width / 2 / 1.28, rect.height / 2 / 1.28)
    let run = r * 1.28
    let pull = r * 0.55
    let path = CGMutablePath()
    let (minX, minY, maxX, maxY) = (rect.minX, rect.minY, rect.maxX, rect.maxY)
    path.move(to: CGPoint(x: minX + run, y: minY))
    path.addLine(to: CGPoint(x: maxX - run, y: minY))
    path.addCurve(to: CGPoint(x: maxX, y: minY + run), control1: CGPoint(x: maxX - pull, y: minY), control2: CGPoint(x: maxX, y: minY + pull))
    path.addLine(to: CGPoint(x: maxX, y: maxY - run))
    path.addCurve(to: CGPoint(x: maxX - run, y: maxY), control1: CGPoint(x: maxX, y: maxY - pull), control2: CGPoint(x: maxX - pull, y: maxY))
    path.addLine(to: CGPoint(x: minX + run, y: maxY))
    path.addCurve(to: CGPoint(x: minX, y: maxY - run), control1: CGPoint(x: minX + pull, y: maxY), control2: CGPoint(x: minX, y: maxY - pull))
    path.addLine(to: CGPoint(x: minX, y: minY + run))
    path.addCurve(to: CGPoint(x: minX + run, y: minY), control1: CGPoint(x: minX, y: minY + pull), control2: CGPoint(x: minX + pull, y: minY))
    path.closeSubpath()
    return path
}

func fill(_ c: CGContext, _ path: CGPath, _ color: CGColor) {
    c.addPath(path)
    c.setFillColor(color)
    c.fillPath()
}

/// A bar of placeholder text: a capsule.
func bar(_ c: CGContext, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, _ color: CGColor) {
    fill(c, continuousRect(CGRect(x: x, y: y, width: width, height: height), radius: height / 2), color)
}

func linearGradient(_ c: CGContext, _ path: CGPath, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    c.saveGState()
    c.addPath(path)
    c.clip()
    let gradient = CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: nil)!
    c.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    c.restoreGState()
}

/// Draws `body` in a card's own coordinates (0…size), centred at `center`, turned by `degrees`,
/// with a soft shadow under the card's shape.
func card(_ c: CGContext, center: CGPoint, size: CGSize, degrees: CGFloat, scale: CGFloat, radius: CGFloat,
          face: CGColor, body: (CGContext) -> Void) {
    c.saveGState()
    c.translateBy(x: center.x, y: center.y)
    c.rotate(by: degrees * .pi / 180)
    c.scaleBy(x: scale, y: scale)
    c.translateBy(x: -size.width / 2, y: -size.height / 2)
    let shape = continuousRect(CGRect(origin: .zero, size: size), radius: radius)
    c.saveGState()
    // A shadow is measured on the canvas, not the card (and the canvas's y runs up), so it is
    // scaled by hand.
    c.setShadow(offset: CGSize(width: 0, height: -26 * scale), blur: 70 * scale, color: color(0x000000, alpha: 0.55))
    fill(c, shape, face)
    c.restoreGState()
    c.saveGState()
    c.addPath(shape)
    c.clip()
    body(c)
    c.restoreGState()
    c.restoreGState()
}

// MARK: - The binder (the app icon's, in its 1024-point coordinates)

/// The icon's binder, its 764-point height drawn `height` tall, centred at `center`.
func binder(_ c: CGContext, center: CGPoint, height: CGFloat) {
    c.saveGState()
    let s = height / 764
    c.translateBy(x: center.x, y: center.y)
    c.scaleBy(x: s, y: s)
    c.translateBy(x: -512, y: -512)

    // The cover, navy with a faint lighter edge, lifted off the background.
    let cover = continuousRect(CGRect(x: 160, y: 130, width: 704, height: 764), radius: 96)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -40 * s), blur: 140 * s, color: color(0x000000, alpha: 0.6))
    fill(c, cover, color(0x1C3366))
    c.restoreGState()
    linearGradient(c, cover, [color(0x22407D), color(0x162A57)], from: CGPoint(x: 512, y: 130), to: CGPoint(x: 512, y: 894))
    c.addPath(cover)
    c.setStrokeColor(color(0x3A5A9C, alpha: 0.7))
    c.setLineWidth(3)
    c.strokePath()

    // The page.
    let page = continuousRect(CGRect(x: 196, y: 172, width: 632, height: 680), radius: 56)
    linearGradient(c, page, [color(0xFFFFFF), color(0xEEF2F9)], from: CGPoint(x: 512, y: 172), to: CGPoint(x: 512, y: 852))

    // What's written on it: a title, a status pill, five lines, and a deadline marked done.
    let line = color(0xCCD6E4)
    bar(c, x: 360, y: 222, width: 190, height: 36, line)
    linearGradient(c, continuousRect(CGRect(x: 580, y: 216, width: 200, height: 48), radius: 24),
                   [color(0x0A84FF), color(0x0B5FDB)], from: CGPoint(x: 580, y: 240), to: CGPoint(x: 780, y: 240))
    for (i, width) in [440, 380, 440, 380, 440].enumerated() {
        bar(c, x: 360, y: 326 + CGFloat(i) * 68, width: CGFloat(width), height: 18, line)
    }
    let done = continuousRect(CGRect(x: 360, y: 696, width: 420, height: 88), radius: 24)
    fill(c, done, color(0xD3EEE4))
    c.addPath(done)
    c.setStrokeColor(color(0x9ADBBF))
    c.setLineWidth(2)
    c.strokePath()
    c.setFillColor(color(0x2DBE60))
    c.fillEllipse(in: CGRect(x: 384, y: 712, width: 56, height: 56))
    c.setStrokeColor(color(0xFFFFFF))
    c.setLineWidth(6)
    c.setLineCap(.round)
    c.setLineJoin(.round)
    c.move(to: CGPoint(x: 398, y: 741))
    c.addLine(to: CGPoint(x: 409, y: 753))
    c.addLine(to: CGPoint(x: 428, y: 728))
    c.strokePath()
    bar(c, x: 460, y: 716, width: 180, height: 18, color(0x34A862))
    bar(c, x: 460, y: 750, width: 120, height: 14, color(0x9DB0C2))

    // The rail and its two rings, brushed metal.
    let rail = continuousRect(CGRect(x: 270, y: 150, width: 44, height: 724), radius: 22)
    linearGradient(c, rail, [color(0xE6EBF2), color(0xFFFFFF), color(0xA9B4C6), color(0xC8D0DC)],
                   from: CGPoint(x: 270, y: 0), to: CGPoint(x: 314, y: 0))
    for y: CGFloat in [243, 780] {
        c.setFillColor(color(0x6E7889))
        c.fillEllipse(in: CGRect(x: 274, y: y - 18, width: 36, height: 36))
        let tab = continuousRect(CGRect(x: 280, y: y - 10, width: 72, height: 20), radius: 10)
        linearGradient(c, tab, [color(0xF4F6FA), color(0xB7C1D0)], from: CGPoint(x: 0, y: y - 10), to: CGPoint(x: 0, y: y + 10))
    }
    c.restoreGState()
}

// MARK: - The papers around it (placeholder shapes, never a real document)

func passport(_ c: CGContext) {
    // A burgundy booklet with a gold emblem and a gold line under it.
    let size = CGSize(width: 300, height: 420)
    linearGradient(c, CGPath(rect: CGRect(origin: .zero, size: size), transform: nil), [color(0x7A2335), color(0x561726)],
                   from: .zero, to: CGPoint(x: size.width, y: size.height))
    c.setStrokeColor(color(0xD9B76E))
    c.setLineWidth(6)
    c.strokeEllipse(in: CGRect(x: 105, y: 120, width: 90, height: 90))
    c.setFillColor(color(0xD9B76E))
    c.fillEllipse(in: CGRect(x: 132, y: 147, width: 36, height: 36))
    bar(c, x: 80, y: 250, width: 140, height: 14, color(0xD9B76E))
    bar(c, x: 105, y: 280, width: 90, height: 10, color(0xD9B76E, alpha: 0.7))
    // The spine's shade.
    c.setFillColor(color(0x000000, alpha: 0.18))
    c.fill(CGRect(x: 0, y: 0, width: 18, height: size.height))
}

func bill(_ c: CGContext) {
    // A page with a coloured header, lines, and its total in a band at the bottom.
    c.setFillColor(color(0xF5A524))
    c.fill(CGRect(x: 0, y: 0, width: 360, height: 70))
    bar(c, x: 30, y: 24, width: 120, height: 22, color(0xFFFFFF, alpha: 0.9))
    let line = color(0xD4DCE8)
    for i in 0..<6 {
        bar(c, x: 30, y: 110 + CGFloat(i) * 42, width: i.isMultiple(of: 2) ? 210 : 170, height: 14, line)
        bar(c, x: 270, y: 110 + CGFloat(i) * 42, width: 60, height: 14, color(0xBAC6D6))
    }
    fill(c, continuousRect(CGRect(x: 24, y: 380, width: 312, height: 64), radius: 18), color(0xFFF2DC))
    bar(c, x: 44, y: 404, width: 110, height: 16, color(0xC98512))
    bar(c, x: 230, y: 398, width: 86, height: 28, color(0xC98512))
}

func policy(_ c: CGContext) {
    // A page with a blue shield and its lines.
    let shield = CGMutablePath()
    shield.move(to: CGPoint(x: 190, y: 48))
    shield.addCurve(to: CGPoint(x: 270, y: 80), control1: CGPoint(x: 215, y: 68), control2: CGPoint(x: 245, y: 78))
    shield.addCurve(to: CGPoint(x: 190, y: 200), control1: CGPoint(x: 272, y: 140), control2: CGPoint(x: 240, y: 180))
    shield.addCurve(to: CGPoint(x: 110, y: 80), control1: CGPoint(x: 140, y: 180), control2: CGPoint(x: 108, y: 140))
    shield.addCurve(to: CGPoint(x: 190, y: 48), control1: CGPoint(x: 135, y: 78), control2: CGPoint(x: 165, y: 68))
    shield.closeSubpath()
    linearGradient(c, shield, [color(0x3B82F6), color(0x1D4ED8)], from: CGPoint(x: 190, y: 48), to: CGPoint(x: 190, y: 200))
    c.setStrokeColor(color(0xFFFFFF))
    c.setLineWidth(10)
    c.setLineCap(.round)
    c.setLineJoin(.round)
    c.move(to: CGPoint(x: 160, y: 122))
    c.addLine(to: CGPoint(x: 182, y: 146))
    c.addLine(to: CGPoint(x: 222, y: 102))
    c.strokePath()
    let line = color(0xD4DCE8)
    bar(c, x: 40, y: 240, width: 300, height: 20, color(0xB9C5D6))
    for i in 0..<5 {
        bar(c, x: 40, y: 290 + CGFloat(i) * 36, width: i.isMultiple(of: 2) ? 300 : 240, height: 13, line)
    }
}

func deadline(_ c: CGContext) {
    // A row from Urmează: a clock in its well, a title and a day.
    fill(c, continuousRect(CGRect(x: 26, y: 31, width: 108, height: 108), radius: 30), color(0xFFE7CC))
    c.setStrokeColor(color(0xF08A00))
    c.setLineWidth(9)
    c.strokeEllipse(in: CGRect(x: 48, y: 53, width: 64, height: 64))
    c.setLineCap(.round)
    c.move(to: CGPoint(x: 80, y: 85))
    c.addLine(to: CGPoint(x: 80, y: 66))
    c.move(to: CGPoint(x: 80, y: 85))
    c.addLine(to: CGPoint(x: 94, y: 94))
    c.strokePath()
    bar(c, x: 160, y: 52, width: 200, height: 24, color(0xB9C5D6))
    bar(c, x: 160, y: 96, width: 130, height: 18, color(0xD4DCE8))
    bar(c, x: 310, y: 94, width: 84, height: 24, color(0xF08A00, alpha: 0.85))
}

func pet(_ c: CGContext) {
    // A pet's card: a green well with a large paw print (PawPaw's), and its lines.
    fill(c, continuousRect(CGRect(x: 26, y: 31, width: 108, height: 108), radius: 30), color(0xD6F2E2))
    let paw = color(0x23A55A)
    c.setFillColor(paw)
    c.fillEllipse(in: CGRect(x: 56, y: 82, width: 48, height: 40))
    for (x, y) in [(46.0, 66.0), (62.0, 50.0), (84.0, 50.0), (100.0, 66.0)] {
        c.fillEllipse(in: CGRect(x: x - 9, y: y - 11, width: 18, height: 22))
    }
    bar(c, x: 160, y: 52, width: 170, height: 24, color(0xB9C5D6))
    bar(c, x: 160, y: 96, width: 220, height: 18, color(0xD4DCE8))
}

func home(_ c: CGContext) {
    // A home's card: a house in a blue well, and its lines.
    fill(c, continuousRect(CGRect(x: 26, y: 31, width: 108, height: 108), radius: 30), color(0xDCE8FF))
    let house = CGMutablePath()
    house.move(to: CGPoint(x: 80, y: 52))
    house.addLine(to: CGPoint(x: 114, y: 82))
    house.addLine(to: CGPoint(x: 104, y: 82))
    house.addLine(to: CGPoint(x: 104, y: 118))
    house.addLine(to: CGPoint(x: 56, y: 118))
    house.addLine(to: CGPoint(x: 56, y: 82))
    house.addLine(to: CGPoint(x: 46, y: 82))
    house.closeSubpath()
    fill(c, house, color(0x2F6FEB))
    fill(c, continuousRect(CGRect(x: 72, y: 96, width: 16, height: 22), radius: 4), color(0xDCE8FF))
    bar(c, x: 160, y: 52, width: 190, height: 24, color(0xB9C5D6))
    bar(c, x: 160, y: 96, width: 150, height: 18, color(0xD4DCE8))
}

// MARK: - Composition

/// Where a paper sits around the binder, in binder heights from the binder's centre.
struct Placement {
    let dx: CGFloat
    let dy: CGFloat
    let degrees: CGFloat
    /// Its size against the binder's height (every paper is smaller than the binder).
    let scale: CGFloat
}

struct Canvas {
    let name: String
    let width: Int
    let height: Int
    /// The safe area Apple gives for the key artwork.
    let safeArea: CGRect
    /// How far the papers spread sideways, in binder heights (a wider canvas spreads them more).
    let spread: CGFloat
}

func render(_ canvas: Canvas) -> CGImage? {
    let (w, h) = (CGFloat(canvas.width), CGFloat(canvas.height))
    guard let c = CGContext(data: nil, width: canvas.width, height: canvas.height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
    // Top-left origin, as the icon's coordinates are.
    c.translateBy(x: 0, y: h)
    c.scaleBy(x: 1, y: -1)
    c.interpolationQuality = .high
    c.setShouldAntialias(true)

    // The icon's background: deep navy, lighter towards the top centre.
    c.setFillColor(color(0x080B14))
    c.fill(CGRect(x: 0, y: 0, width: w, height: h))
    let glow = CGGradient(colorsSpace: sRGB, colors: [color(0x1E2F5C), color(0x111A33), color(0x080B14)] as CFArray, locations: [0, 0.45, 1])!
    c.drawRadialGradient(glow, startCenter: CGPoint(x: w / 2, y: h * 0.18), startRadius: 0,
                         endCenter: CGPoint(x: w / 2, y: h * 0.18), endRadius: max(w, h) * 0.75, options: [.drawsAfterEndLocation])
    let center = CGPoint(x: canvas.safeArea.midX, y: canvas.safeArea.midY)
    let halo = CGGradient(colorsSpace: sRGB, colors: [color(0x2D6BFF, alpha: 0.28), color(0x2D6BFF, alpha: 0)] as CFArray, locations: [0, 1])!
    let binderHeight = canvas.safeArea.height * 0.96
    c.drawRadialGradient(halo, startCenter: center, startRadius: 0, endCenter: center, endRadius: binderHeight * 1.1, options: [])

    // The papers, farther ones first, then the binder over them.
    let u = binderHeight
    let s = canvas.spread
    let papers: [(Placement, CGSize, CGFloat, CGColor, (CGContext) -> Void)] = [
        (Placement(dx: -1.78 * s, dy: -0.20, degrees: 8, scale: 0.00125), CGSize(width: 360, height: 470), 26, color(0xFFFFFF), bill),
        (Placement(dx: 1.80 * s, dy: -0.26, degrees: -6, scale: 0.00125), CGSize(width: 420, height: 170), 34, color(0xFFFFFF), deadline),
        (Placement(dx: -1.80 * s, dy: 0.36, degrees: -5, scale: 0.00125), CGSize(width: 400, height: 170), 34, color(0xFFFFFF), home),
        (Placement(dx: 1.78 * s, dy: 0.30, degrees: 5, scale: 0.00125), CGSize(width: 400, height: 170), 34, color(0xFFFFFF), pet),
        (Placement(dx: -1.02 * s, dy: 0.05, degrees: -10, scale: 0.0014), CGSize(width: 300, height: 420), 30, color(0x6B1F2E), passport),
        (Placement(dx: 1.03 * s, dy: 0.03, degrees: 8, scale: 0.00128), CGSize(width: 380, height: 500), 28, color(0xFFFFFF), policy),
    ]
    for (place, size, radius, face, draw) in papers {
        card(c, center: CGPoint(x: center.x + place.dx * u, y: center.y + place.dy * u), size: size, degrees: place.degrees,
             scale: place.scale * u, radius: radius, face: face, body: draw)
    }
    binder(c, center: center, height: binderHeight)
    return c.makeImage()
}

func writePNG(_ image: CGImage, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

let canvases = [
    Canvas(name: "header-3840x1646", width: 3840, height: 1646,
           safeArea: CGRect(x: 1097, y: 493, width: 1646, height: 661), spread: 1.0),
    Canvas(name: "search-3840x2560", width: 3840, height: 2560,
           safeArea: CGRect(x: 836, y: 765, width: 2168, height: 1030), spread: 0.86),
]

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: swift marketing/header-art.swift <output folder>\n".utf8))
    exit(2)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
for canvas in canvases {
    guard let image = render(canvas) else {
        FileHandle.standardError.write(Data("Couldn't draw \(canvas.name).\n".utf8))
        exit(1)
    }
    try writePNG(image, to: output.appending(path: "\(canvas.name).png"))
    print("\(canvas.name).png")
}
