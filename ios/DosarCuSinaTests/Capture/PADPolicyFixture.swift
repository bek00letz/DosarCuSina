import CoreGraphics
import CoreText
import Foundation

/// A made-up PAD policy (the mandatory home insurance), laid out as such policies are: the
/// seller's notice on data protection first, then the policy's page, a form whose labels and
/// values are printed as separate pieces of text in their own places, a row of labels printed
/// as one run with each value in a gap of it. Every name, number, address, amount and date is
/// a placeholder.
enum PADPolicyFixture {
    /// A piece of text, where its top-left corner sits on an A4 page (in points from the
    /// page's top-left), and its size.
    struct Piece {
        let text: String
        let x: CGFloat
        let y: CGFloat
        var size: CGFloat = 9
        /// A label is printed bold, a value plain, as a form prints them.
        var isLabel = false
    }

    static let seller = "VÂNZĂTOR EXEMPLU ASIGURĂRI S.A."
    static let address = "Jud. Exemplu, UAT Exemplu, Loc. Exemplu, Str. Exemplu, Nr. 1, Ap. 2, CP 000000"

    /// The seller's notice, which names the seller, its own tax ID and address, and words a
    /// policy's labels use ("asigurat", "adresa") in its sentences.
    static let notice: [Piece] = [
        Piece(text: "NOTĂ DE INFORMARE PRIVIND PRELUCRAREA DATELOR CU CARACTER PERSONAL", x: 40, y: 40),
        Piece(text: "\(seller), cu sediul în București, Str. Exemplu nr. 9, CUI 11111110, colectează și prelucrează datele", x: 40, y: 60),
        Piece(text: "personale pentru întocmirea dosarelor de daune în cazul apariției riscului asigurat (inclusiv ocupația", x: 40, y: 72),
        Piece(text: "și experiența profesională) și pentru calculul primelor de asigurare.", x: 40, y: 84),
        Piece(text: "Ne puteți scrie prin poștă la adresa: București, Str. Exemplu nr. 9, sector 1.", x: 40, y: 108),
        Piece(text: "Prezenta notă de informare reprezintă versiunea din data de 01.01.2020", x: 40, y: 132),
    ]

    /// The policy's page, its pieces where such a policy prints them.
    static let policy: [Piece] = [
        Piece(text: "PAID EXEMPLU - POOL-UL DE ASIGURARE ÎMPOTRIVA DEZASTRELOR NATURALE S.A.", x: 225, y: 15),
        Piece(text: "Str. Exemplu nr. 3, București, Sector 1", x: 225, y: 29),
        Piece(text: "J00/000/2009; CUI 12345674", x: 225, y: 42),
        Piece(text: "prin:", x: 225, y: 72),
        Piece(text: seller, x: 247, y: 72),
        Piece(text: "Str. Exemplu nr. 9, București", x: 225, y: 87),
        Piece(text: "CUI 11111110", x: 225, y: 100),
        // The labels as one run, the values in its gaps, a little lower and smaller.
        Piece(text: "Seria:              Nr:                         reînnoiește PAD Seria:              Nr:", x: 225, y: 130, isLabel: true),
        Piece(text: "RA-000", x: 252, y: 131.5, size: 8.5),
        Piece(text: "0000000012", x: 300, y: 131.5, size: 8.5),
        Piece(text: "RA-000", x: 459, y: 131.5, size: 8.5),
        Piece(text: "0000000013", x: 507, y: 131.5, size: 8.5),
        Piece(text: "ASIGURAREA OBLIGATORIE A LOCUINȚEI ÎN BAZA LEGII NR. 260/2008", x: 27, y: 150),
        Piece(text: "ASIGURAT:", x: 25, y: 184),
        Piece(text: "EXEMPLU ION", x: 94, y: 184.5, size: 8.5),
        Piece(text: "Telefon: - ; E-mail: -", x: 94, y: 197, size: 8.5),
        Piece(text: "CNP/CUI: 1800101990006; \(address)", x: 94, y: 210, size: 8.5),
        Piece(text: "CONTRACTANT:", x: 24, y: 236),
        Piece(text: "EXEMPLU ION", x: 94, y: 237.5, size: 8.5),
        Piece(text: "CNP/CUI: 1800101990006; \(address)", x: 94, y: 263, size: 8.5),
        Piece(text: "PERIOADĂ DE VALABILITATE:", x: 25, y: 288),
        Piece(text: "1", x: 205, y: 290, size: 8.5),
        Piece(text: "AN", x: 218, y: 288),
        Piece(text: "De la:", x: 304, y: 288),
        Piece(text: "01.12.2026", x: 337, y: 290, size: 8.5),
        Piece(text: "Până la:", x: 400, y: 288),
        Piece(text: "30.11.2027", x: 440, y: 290, size: 8.5),
        Piece(text: "SUMĂ ASIGURATĂ:", x: 25, y: 302),
        Piece(text: "50.000", x: 180, y: 302.5, size: 8.5),
        Piece(text: "LEI", x: 218, y: 301),
        Piece(text: "TIP LOCUINȚĂ:", x: 267, y: 300),
        Piece(text: "A", x: 336, y: 302.5, size: 8.5),
        Piece(text: "PRIMA DE ASIGURARE:", x: 25, y: 316),
        Piece(text: "100", x: 195, y: 314.5, size: 8.5),
        Piece(text: "LEI", x: 218, y: 312.5),
        Piece(text: "încasată în data de:", x: 249, y: 312),
        Piece(text: "25.11.2026", x: 336, y: 314.5, size: 8.5),
        Piece(text: "LOCUINȚA ASIGURATĂ:", x: 25, y: 336),
        Piece(text: "Adresă:", x: 25, y: 349),
        Piece(text: address, x: 63, y: 350.5, size: 8.5),
        Piece(text: "Identificare locuință asigurată:", x: 25, y: 380),
        Piece(text: "Suprafață utilă m2: 50,00   Număr camere: 2   An construcție: 2000", x: 25, y: 394),
        Piece(text: "Prezentul contract de asigurare a fost emis electronic în data de 25.11.2026 și este distribuit de \(seller)", x: 25, y: 570),
        Piece(text: "Prin plata primei de asigurare Asiguratul/Contractantul confirmă că a luat cunoștință de prevederile legii.", x: 27, y: 800),
    ]

    /// The PDF: the notice on two pages, then the policy.
    static func pdf() -> Data {
        let data = NSMutableData()
        var page = CGRect(x: 0, y: 0, width: 595.32, height: 841.92)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &page, nil) else { return Data() }
        for pieces in [Array(notice.prefix(4)), Array(notice.dropFirst(4)), policy] {
            context.beginPDFPage(nil)
            for piece in pieces { draw(piece, in: context, pageHeight: page.height) }
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    private static func draw(_ piece: Piece, in context: CGContext, pageHeight: CGFloat) {
        let font = CTFontCreateWithName((piece.isLabel ? "Helvetica-Bold" : "Helvetica") as CFString, piece.size, nil)
        let text = NSAttributedString(string: piece.text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let line = CTLineCreateWithAttributedString(text)
        context.textPosition = CGPoint(x: piece.x, y: pageHeight - piece.y - CTFontGetAscent(font))
        CTLineDraw(line, context)
    }
}
