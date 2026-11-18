#if DEBUG
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The pictures of the App Store screenshots' household, drawn here in code (nothing downloaded,
/// nothing generated elsewhere), in development builds only: PawPaw, a grey tabby with green eyes,
/// a white belly and large paws, and a passport's data page that is plainly a specimen, with
/// made-up values only (a CNP of county 99, a made-up number and its machine-readable lines).
/// Each draws on a context whose origin is the top left, in points of `size`.
enum ScreenshotPictures {
    // MARK: Drawing a picture

    /// A JPEG of `width` × `height` pixels drawn by `draw` on the app's one bitmap canvas
    /// (`ImageScaling.canvas`), flipped so its origin is the top left.
    static func jpeg(width: Int, height: Int, _ draw: (CGSize, CGContext) -> Void) -> Data? {
        guard let context = ImageScaling.canvas(width: width, height: height, onWhite: true) else { return nil }
        flipped(context, height: CGFloat(height))
        draw(CGSize(width: width, height: height), context)
        guard let image = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    // MARK: Colours and text

    static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    /// One line of text with its baseline's left end at `point`, in a context flipped to the top left.
    static func text(_ string: String, at point: CGPoint, size: CGFloat, font name: String? = nil, bold: Bool = false,
                     color: CGColor, tracking: CGFloat = 0, in context: CGContext) {
        let font: CTFont
        if let name {
            font = CTFontCreateWithName(name as CFString, size, nil)
        } else {
            let system = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
            font = system
        }
        let attributes: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color, kCTKernAttributeName: tracking]
        let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, string as CFString, attributes as CFDictionary))
        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = point
        CTLineDraw(line, context)
        context.restoreGState()
    }

    /// Flips `context` so its origin is the top left, as every drawing here expects.
    static func flipped(_ context: CGContext, height: CGFloat) {
        context.translateBy(x: 0, y: height)
        context.scaleBy(x: 1, y: -1)
    }

    // MARK: The specimen passport

    /// What the specimen's page says. Every value is made up.
    struct Passport {
        var surname = "DOSARESCU"
        var givenNames = "ANA"
        var number = "050000000"
        /// A CNP of county 99 (made up) with its control digit.
        var personalNumber = "2800101990008"
        var birth = (year: 1980, month: 1, day: 1)
        var issued: (year: Int, month: Int, day: Int)
        var expires: (year: Int, month: Int, day: Int)
    }

    private static let months = ["IAN/JAN", "FEB/FEB", "MAR/MAR", "APR/APR", "MAI/MAY", "IUN/JUN", "IUL/JUL", "AUG/AUG", "SEP/SEP", "OCT/OCT", "NOI/NOV", "DEC/DEC"]

    private static func printed(_ day: (year: Int, month: Int, day: Int)) -> String {
        let dd = day.day < 10 ? "0\(day.day)" : "\(day.day)"
        return "\(dd) \(months[max(0, min(11, day.month - 1))]) \(day.year)"
    }

    /// The check digit of a machine-readable field: weights 7, 3, 1; letters count from 10, "<" as 0.
    static func checkDigit(_ field: String) -> Character {
        let weights = [7, 3, 1]
        var sum = 0
        for (index, character) in field.enumerated() {
            let value: Int
            if let digit = character.wholeNumberValue { value = digit }
            else if let ascii = character.asciiValue, character.isLetter { value = Int(ascii) - 55 }
            else { value = 0 }
            sum += value * weights[index % 3]
        }
        return Character(String(sum % 10))
    }

    private static func yymmdd(_ day: (year: Int, month: Int, day: Int)) -> String {
        func two(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }
        return two(day.year % 100) + two(day.month) + two(day.day)
    }

    private static func padded(_ string: String, to length: Int) -> String {
        String((string + String(repeating: "<", count: length)).prefix(length))
    }

    /// The two machine-readable lines of the specimen, 44 characters each, with valid check digits.
    static func machineLines(_ passport: Passport) -> [String] {
        let first = padded("P<ROU" + passport.surname + "<<" + passport.givenNames.replacingOccurrences(of: " ", with: "<"), to: 44)
        let number = padded(passport.number, to: 9)
        let birth = yymmdd(passport.birth)
        let expiry = yymmdd(passport.expires)
        let personal = padded(passport.personalNumber, to: 14)
        let composite = number + String(checkDigit(number)) + birth + String(checkDigit(birth)) + expiry + String(checkDigit(expiry))
            + personal + String(checkDigit(personal))
        let second = number + String(checkDigit(number)) + "ROU" + birth + String(checkDigit(birth)) + "F" + expiry + String(checkDigit(expiry))
            + personal + String(checkDigit(personal)) + String(checkDigit(composite))
        return [first, second]
    }

    /// The data page, landscape, in proportion to a passport's (125 × 88 mm).
    static func drawPassport(_ passport: Passport, size: CGSize, in context: CGContext) {
        let w = size.width, h = size.height
        let unit = w / 1250
        // The page: a pale pink and lilac paper with fine guilloche waves.
        let paper = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [rgb(0xF7E9EF), rgb(0xE9E6F5), rgb(0xF3EADF)] as CFArray, locations: [0, 0.55, 1])!
        context.drawLinearGradient(paper, start: .zero, end: CGPoint(x: w, y: h), options: [])
        context.setLineWidth(1.2 * unit)
        for line in 0..<46 {
            let base = CGFloat(line) * h / 40 - h * 0.08
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: base))
            for step in stride(from: 0, through: w, by: 6 * unit) {
                let wave = sin(step / (70 * unit) + CGFloat(line) * 0.45) * 14 * unit + sin(step / (23 * unit)) * 3 * unit
                path.addLine(to: CGPoint(x: step, y: base + wave))
            }
            context.addPath(path)
            context.setStrokeColor(line % 2 == 0 ? rgb(0xC9A7C7, 0.45) : rgb(0xA9B8DA, 0.40))
            context.strokePath()
        }
        // A rosette behind the values.
        let rosette = CGPoint(x: w * 0.72, y: h * 0.42)
        for ring in 0..<28 {
            let path = CGMutablePath()
            let radius = (60 + CGFloat(ring) * 6) * unit
            for step in 0...180 {
                let angle = CGFloat(step) / 180 * 2 * .pi
                let r = radius + sin(angle * 12 + CGFloat(ring)) * 6 * unit
                let point = CGPoint(x: rosette.x + cos(angle) * r, y: rosette.y + sin(angle) * r * 0.8)
                step == 0 ? path.move(to: point) : path.addLine(to: point)
            }
            context.addPath(path)
            context.setStrokeColor(rgb(0xB79BC4, 0.22))
            context.strokePath()
        }

        let ink = rgb(0x1E2233), label = rgb(0x5B4C6B)
        text("ROMÂNIA  ·  ROUMANIE  ·  ROMANIA", at: CGPoint(x: 60 * unit, y: 70 * unit), size: 30 * unit, bold: true, color: rgb(0x3B2E5A), tracking: 2 * unit, in: context)
        text("PAȘAPORT  ·  PASSEPORT  ·  PASSPORT", at: CGPoint(x: 60 * unit, y: 108 * unit), size: 22 * unit, color: rgb(0x3B2E5A), tracking: 1.5 * unit, in: context)

        // The portrait: a drawn silhouette, never a face.
        let photo = CGRect(x: 60 * unit, y: 150 * unit, width: 300 * unit, height: 380 * unit)
        let backdrop = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [rgb(0xDDE3EC), rgb(0xC5CEDB)] as CFArray, locations: [0, 1])!
        context.saveGState()
        context.addPath(CGPath(roundedRect: photo, cornerWidth: 10 * unit, cornerHeight: 10 * unit, transform: nil))
        context.clip()
        context.drawLinearGradient(backdrop, start: CGPoint(x: photo.midX, y: photo.minY), end: CGPoint(x: photo.midX, y: photo.maxY), options: [])
        context.setFillColor(rgb(0x8A93A3))
        context.fillEllipse(in: CGRect(x: photo.midX - 78 * unit, y: photo.minY + 70 * unit, width: 156 * unit, height: 190 * unit))
        context.fillEllipse(in: CGRect(x: photo.midX - 150 * unit, y: photo.minY + 270 * unit, width: 300 * unit, height: 240 * unit))
        context.restoreGState()
        // The small ghost portrait beside the values.
        context.setFillColor(rgb(0x8A93A3, 0.22))
        context.fillEllipse(in: CGRect(x: 1080 * unit, y: 400 * unit, width: 70 * unit, height: 86 * unit))
        context.fillEllipse(in: CGRect(x: 1050 * unit, y: 490 * unit, width: 130 * unit, height: 90 * unit))

        // The values, each under its label in Romanian and English.
        func field(_ caption: String, _ value: String, x: CGFloat, y: CGFloat) {
            text(caption, at: CGPoint(x: x * unit, y: y * unit), size: 15 * unit, color: label, in: context)
            text(value, at: CGPoint(x: x * unit, y: (y + 30) * unit), size: 25 * unit, bold: true, color: ink, in: context)
        }
        field("Tip / Type", "P", x: 400, y: 170)
        field("Cod țară / Code", "ROU", x: 530, y: 170)
        field("Pașaport nr. / Passport No.", passport.number, x: 720, y: 170)
        field("Nume / Surname", passport.surname, x: 400, y: 240)
        field("Prenume / Given names", passport.givenNames, x: 400, y: 310)
        field("Cetățenie / Nationality", "ROMÂNĂ / ROU", x: 400, y: 380)
        field("Data nașterii / Date of birth", printed(passport.birth), x: 400, y: 450)
        field("CNP / Personal No.", passport.personalNumber, x: 760, y: 450)
        field("Sex", "F", x: 400, y: 520)
        field("Locul nașterii / Place of birth", "ROU", x: 520, y: 520)
        field("Data eliberării / Date of issue", printed(passport.issued), x: 400, y: 590)
        field("Data expirării / Date of expiry", printed(passport.expires), x: 760, y: 590)
        // A signature: one quick stroke.
        let signature = CGMutablePath()
        signature.move(to: CGPoint(x: 90 * unit, y: 600 * unit))
        signature.addCurve(to: CGPoint(x: 190 * unit, y: 580 * unit), control1: CGPoint(x: 120 * unit, y: 540 * unit), control2: CGPoint(x: 150 * unit, y: 640 * unit))
        signature.addCurve(to: CGPoint(x: 320 * unit, y: 585 * unit), control1: CGPoint(x: 230 * unit, y: 530 * unit), control2: CGPoint(x: 260 * unit, y: 630 * unit))
        context.addPath(signature)
        context.setStrokeColor(rgb(0x2B3A78, 0.85))
        context.setLineWidth(3 * unit)
        context.setLineCap(.round)
        context.strokePath()

        // The machine-readable zone.
        context.setFillColor(rgb(0xFFFFFF, 0.55))
        context.fill(CGRect(x: 0, y: h - 190 * unit, width: w, height: 190 * unit))
        for (index, line) in machineLines(passport).enumerated() {
            text(line, at: CGPoint(x: 52 * unit, y: h - (120 - CGFloat(index) * 62) * unit), size: 42.5 * unit, font: "Courier-Bold", color: ink, in: context)
        }

        // SPECIMEN, across the whole page.
        context.saveGState()
        context.translateBy(x: w / 2, y: h * 0.46)
        context.rotate(by: -0.38)
        text("SPECIMEN", at: CGPoint(x: -470 * unit, y: 70 * unit), size: 200 * unit, bold: true, color: rgb(0xD22B3C, 0.30), tracking: 18 * unit, in: context)
        context.restoreGState()
    }

    // MARK: PawPaw

    /// PawPaw, sitting: a grey tabby with green eyes, a white belly and large paws.
    static func drawPawPaw(size: CGSize, in context: CGContext) {
        let w = size.width, h = size.height
        let u = w / 1000
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * u, y: y * u) }
        func r(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect { CGRect(x: x * u, y: y * u, width: width * u, height: height * u) }
        let space = CGColorSpace(name: CGColorSpace.sRGB)

        // A warm room behind him, and the cushion he sits on.
        let wall = CGGradient(colorsSpace: space, colors: [rgb(0xF2E6D6), rgb(0xE4D2BC)] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(wall, start: .zero, end: CGPoint(x: 0, y: h), options: [])
        context.setFillColor(rgb(0xB7C7B0))
        context.fillEllipse(in: r(110, 820, 780, 170))
        context.setFillColor(rgb(0xA3B59B))
        context.fillEllipse(in: r(150, 850, 700, 120))

        let fur = rgb(0x8C9198), furDark = rgb(0x6E737B), stripe = rgb(0x4A4E55), white = rgb(0xF6F3EE)
        func fill(_ path: CGPath, _ color: CGColor) { context.addPath(path); context.setFillColor(color); context.fillPath() }
        func stroke(_ path: CGPath, _ color: CGColor, _ width: CGFloat) {
            context.addPath(path); context.setStrokeColor(color); context.setLineWidth(width * u); context.setLineCap(.round); context.strokePath()
        }

        // The tail, from behind him on his right, along the cushion and round in front of his paws.
        let tail = CGMutablePath()
        tail.move(to: p(700, 760))
        tail.addCurve(to: p(820, 880), control1: p(800, 760), control2: p(860, 830))
        tail.addCurve(to: p(560, 905), control1: p(760, 930), control2: p(650, 920))
        stroke(tail, rgb(0x858A91), 58)
        // Its rings, kept inside the tail.
        context.saveGState()
        context.addPath(tail)
        context.setLineWidth(58 * u)
        context.replacePathWithStrokedPath()
        context.clip()
        for (x, y, angle) in [(790, 805, 0.9), (800, 895, -0.6), (690, 915, -0.15), (610, 908, 0.05)] as [(CGFloat, CGFloat, CGFloat)] {
            let band = CGMutablePath()
            band.move(to: p(x - sin(angle) * 40, y + cos(angle) * 40))
            band.addLine(to: p(x + sin(angle) * 40, y - cos(angle) * 40))
            stroke(band, stripe, 14)
        }
        context.restoreGState()

        // The body: a soft pear, with the tabby's stripes down his sides.
        let body = CGMutablePath()
        body.move(to: p(500, 420))
        body.addCurve(to: p(760, 860), control1: p(700, 420), control2: p(800, 700))
        body.addLine(to: p(240, 860))
        body.addCurve(to: p(500, 420), control1: p(200, 700), control2: p(300, 420))
        body.closeSubpath()
        fill(body, fur)
        context.saveGState()
        context.addPath(body)
        context.clip()
        let shade = CGGradient(colorsSpace: space, colors: [rgb(0xFFFFFF, 0.14), rgb(0x000000, 0.12)] as CFArray, locations: [0.35, 1])!
        context.drawRadialGradient(shade, startCenter: p(500, 600), startRadius: 0, endCenter: p(500, 640), endRadius: 330 * u, options: [.drawsAfterEndLocation])
        for (index, y) in [520, 590, 660, 730, 800].enumerated() {
            let left = CGMutablePath()
            left.move(to: p(220, CGFloat(y) + 10))
            left.addQuadCurve(to: p(345, CGFloat(y) - 20 + CGFloat(index % 2) * 10), control: p(290, CGFloat(y) - 30))
            stroke(left, stripe, 22)
            let right = CGMutablePath()
            right.move(to: p(780, CGFloat(y) + 10))
            right.addQuadCurve(to: p(655, CGFloat(y) - 20 + CGFloat(index % 2) * 10), control: p(710, CGFloat(y) - 30))
            stroke(right, stripe, 22)
        }
        context.restoreGState()

        // The white belly and chest.
        let belly = CGMutablePath()
        belly.move(to: p(500, 470))
        belly.addCurve(to: p(615, 860), control1: p(610, 500), control2: p(650, 760))
        belly.addLine(to: p(385, 860))
        belly.addCurve(to: p(500, 470), control1: p(350, 760), control2: p(390, 500))
        belly.closeSubpath()
        fill(belly, white)

        // The front legs, and the large paws.
        for x in [400, 600] as [CGFloat] {
            let leg = CGPath(roundedRect: r(x - 54, 640, 108, 230), cornerWidth: 52 * u, cornerHeight: 52 * u, transform: nil)
            fill(leg, fur)
            context.saveGState()
            context.addPath(leg)
            context.clip()
            for y in [700, 755, 810] as [CGFloat] {
                let band = CGMutablePath()
                band.move(to: p(x - 60, y))
                band.addQuadCurve(to: p(x + 60, y), control: p(x, y + 22))
                stroke(band, stripe, 13)
            }
            context.restoreGState()
            let paw = r(x - 80, 826, 160, 78)
            fill(CGPath(ellipseIn: paw, transform: nil), rgb(0x9A9FA6))
            fill(CGPath(ellipseIn: r(x - 80, 826, 160, 30), transform: nil), rgb(0xFFFFFF, 0.10))
            for toe in [-30, 0, 30] as [CGFloat] {
                let crease = CGMutablePath()
                crease.move(to: p(x + toe * 0.8, 862))
                crease.addLine(to: p(x + toe, 900))
                stroke(crease, furDark, 5)
            }
        }

        // The head: wide cheeks and two ears with pink inside.
        for side in [-1, 1] as [CGFloat] {
            let ear = CGMutablePath()
            ear.move(to: p(500 + side * 70, 175))
            ear.addQuadCurve(to: p(500 + side * 205, 60), control: p(500 + side * 150, 90))
            ear.addQuadCurve(to: p(500 + side * 225, 240), control: p(500 + side * 235, 150))
            ear.closeSubpath()
            fill(ear, fur)
            let inner = CGMutablePath()
            inner.move(to: p(500 + side * 100, 185))
            inner.addQuadCurve(to: p(500 + side * 195, 95), control: p(500 + side * 150, 115))
            inner.addQuadCurve(to: p(500 + side * 205, 215), control: p(500 + side * 210, 160))
            inner.closeSubpath()
            fill(inner, rgb(0xE6B3AE))
        }
        let head = CGMutablePath()
        head.move(to: p(500, 140))
        head.addCurve(to: p(745, 330), control1: p(650, 140), control2: p(745, 210))
        head.addCurve(to: p(500, 520), control1: p(745, 460), control2: p(640, 520))
        head.addCurve(to: p(255, 330), control1: p(360, 520), control2: p(255, 460))
        head.addCurve(to: p(500, 140), control1: p(255, 210), control2: p(350, 140))
        head.closeSubpath()
        fill(head, fur)
        context.saveGState()
        context.addPath(head)
        context.clip()
        // The tabby's M on the forehead, and stripes on the cheeks.
        let mark = CGMutablePath()
        mark.move(to: p(440, 255))
        mark.addLine(to: p(462, 185))
        mark.addLine(to: p(500, 235))
        mark.addLine(to: p(538, 185))
        mark.addLine(to: p(560, 255))
        stroke(mark, stripe, 11)
        for offset in [-1, 0, 1] as [CGFloat] {
            let line = CGMutablePath()
            line.move(to: p(500 + offset * 26, 150))
            line.addLine(to: p(500 + offset * 20, 190))
            stroke(line, stripe, 12)
        }
        for side in [-1, 1] as [CGFloat] {
            for (index, y) in [350, 385].enumerated() {
                let cheek = CGMutablePath()
                cheek.move(to: p(500 + side * 255, CGFloat(y)))
                cheek.addQuadCurve(to: p(500 + side * 175, CGFloat(y) + 8 + CGFloat(index) * 6), control: p(500 + side * 215, CGFloat(y) - 14))
                stroke(cheek, stripe, 12)
            }
        }
        context.restoreGState()
        // The white muzzle and chin.
        fill(CGPath(ellipseIn: r(415, 370, 85, 80), transform: nil), white)
        fill(CGPath(ellipseIn: r(500, 370, 85, 80), transform: nil), white)
        fill(CGPath(ellipseIn: r(450, 420, 100, 70), transform: nil), white)

        // Green eyes, almond-shaped, with slit pupils and a glint.
        for side in [-1, 1] as [CGFloat] {
            let centre = p(500 + side * 95, 300)
            let eye = CGMutablePath()
            eye.move(to: CGPoint(x: centre.x - 52 * u, y: centre.y + 2 * u))
            eye.addCurve(to: CGPoint(x: centre.x + 52 * u, y: centre.y - 6 * u * side), control1: CGPoint(x: centre.x - 40 * u, y: centre.y - 46 * u), control2: CGPoint(x: centre.x + 36 * u, y: centre.y - 50 * u))
            eye.addCurve(to: CGPoint(x: centre.x - 52 * u, y: centre.y + 2 * u), control1: CGPoint(x: centre.x + 40 * u, y: centre.y + 44 * u), control2: CGPoint(x: centre.x - 36 * u, y: centre.y + 46 * u))
            eye.closeSubpath()
            context.saveGState()
            context.addPath(eye)
            context.clip()
            let iris = CGGradient(colorsSpace: space, colors: [rgb(0xB7DA6A), rgb(0x5E9C34)] as CFArray, locations: [0, 1])!
            context.drawRadialGradient(iris, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: 60 * u, options: [])
            context.restoreGState()
            stroke(eye, rgb(0x2E3136), 6)
            fill(CGPath(ellipseIn: CGRect(x: centre.x - 12 * u, y: centre.y - 34 * u, width: 24 * u, height: 68 * u), transform: nil), rgb(0x15171A))
            fill(CGPath(ellipseIn: CGRect(x: centre.x + 12 * u, y: centre.y - 24 * u, width: 14 * u, height: 14 * u), transform: nil), rgb(0xFFFFFF, 0.9))
        }

        // A pink nose, the mouth and long whiskers.
        let nose = CGMutablePath()
        nose.move(to: p(475, 380))
        nose.addLine(to: p(525, 380))
        nose.addQuadCurve(to: p(500, 410), control: p(520, 400))
        nose.addQuadCurve(to: p(475, 380), control: p(480, 400))
        nose.closeSubpath()
        fill(nose, rgb(0xD98C8C))
        let mouth = CGMutablePath()
        mouth.move(to: p(500, 410))
        mouth.addLine(to: p(500, 428))
        mouth.addQuadCurve(to: p(468, 436), control: p(486, 442))
        mouth.move(to: p(500, 428))
        mouth.addQuadCurve(to: p(532, 436), control: p(514, 442))
        stroke(mouth, rgb(0x6B5B5B), 5)
        for side in [-1, 1] as [CGFloat] {
            for (index, lift) in [-22, 0, 22].enumerated() {
                let whisker = CGMutablePath()
                whisker.move(to: p(500 + side * 70, 410 + CGFloat(index) * 10))
                whisker.addQuadCurve(to: p(500 + side * 300, 390 + CGFloat(lift) * 1.6), control: p(500 + side * 190, 395 + CGFloat(lift)))
                stroke(whisker, rgb(0xFFFFFF, 0.85), 3.5)
            }
        }
    }
}
#endif
