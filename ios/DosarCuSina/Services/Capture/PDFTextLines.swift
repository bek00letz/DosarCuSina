import Foundation
import PDFKit

/// A digital PDF's text with where each line sits on its page, read like a photo's lines
/// (`RecognizedLine`), so every reader finds a value beside or under its label the same
/// way for a photo, a scan and a PDF.
///
/// A PDF's plain text keeps the order its producer wrote the text in, which for a form is
/// often every label first and every value after them: "De la:" and "Până la:" far from
/// their days. Its lines keep their places, so the lines are taken with their bounds and
/// put in reading order by `TextLayout`, as recognition's are.
///
/// A form may also print a row of labels as one run of text with gaps ("Seria:   Nr:")
/// and its values as another run, or several, in those gaps. Where runs on a row cross each
/// other like that, the row is read again piece by piece, each piece of text where the page
/// prints it, so each label is followed by its value. When the pieces don't spell those
/// runs exactly, the runs stay as they are.
enum PDFTextLines {
    /// The lines of each page, in reading order, for the first `maxPages` pages. Empty for a
    /// PDF PDFKit can't open; a page without a text layer has none.
    static func pages(of data: Data, maxPages: Int) -> [[RecognizedLine]] {
        guard let document = PDFDocument(data: data) else { return [] }
        return (0..<min(document.pageCount, maxPages)).compactMap { document.page(at: $0) }.map(lines(on:))
    }

    /// One page's lines, in reading order.
    static func lines(on page: PDFPage) -> [RecognizedLine] {
        let area = page.bounds(for: .cropBox)
        guard area.width > 0, area.height > 0, let all = page.selection(for: area) else { return [] }
        let runs = pieces(of: all, on: page)
        let read = crossings(among: runs).flatMap { group in group.count > 1 ? apart(group, on: page) : group }
        return TextLayout.arrange(read.map { RecognizedLine($0.text, box: box(of: $0.bounds, on: page, area: area)) })
    }

    // MARK: - Runs

    /// A run of text as the PDF's producer wrote it, in page space.
    struct Run {
        let text: String
        let bounds: CGRect

        /// Whether the two sit on one row and cross: one starts inside the other's span.
        func crosses(_ other: Run) -> Bool {
            let shared = min(bounds.maxY, other.bounds.maxY) - max(bounds.minY, other.bounds.minY)
            guard shared >= 0.5 * min(bounds.height, other.bounds.height) else { return false }
            return min(bounds.maxX, other.bounds.maxX) > max(bounds.minX, other.bounds.minX)
        }
    }

    /// The runs a selection holds, one per line, with their bounds.
    private static func pieces(of selection: PDFSelection, on page: PDFPage) -> [Run] {
        selection.selectionsByLine().compactMap { line in
            guard let text = line.string.map(oneLine), !text.isEmpty else { return nil }
            let bounds = line.bounds(for: page)
            guard bounds.width > 0, bounds.height > 0 else { return nil }
            return Run(text: text, bounds: bounds)
        }
    }

    /// Text on one line, its spaces as one.
    private static func oneLine(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }

    /// The runs in groups that cross each other (a row of labels and the values in its gaps);
    /// a run that crosses none is a group of its own.
    static func crossings(among runs: [Run]) -> [[Run]] {
        var groups: [[Run]] = []
        for run in runs {
            let joined = groups.indices.filter { index in groups[index].contains { $0.crosses(run) } }
            guard let first = joined.first else {
                groups.append([run])
                continue
            }
            for index in joined.dropFirst().reversed() { groups[first] += groups.remove(at: index) }
            groups[first].append(run)
        }
        return groups
    }

    /// How finely a row is looked along for its letters, in points: narrower than any letter.
    static let probeStep: CGFloat = 1
    /// The widest gap inside a word, as a share of the row's height: smaller than a space.
    static let wordGapRatio: CGFloat = 0.15

    /// Runs that cross, read again piece by piece: the page is looked along their row for
    /// where its letters are printed, letters closer than a space make a word, and each word
    /// is read where it is printed. The runs as they were when the words don't spell exactly
    /// what they held.
    static func apart(_ runs: [Run], on page: PDFPage) -> [Run] {
        let row = runs.dropFirst().reduce(runs[0].bounds) { $0.union($1.bounds) }
        func band(_ from: CGFloat, _ to: CGFloat) -> CGRect { CGRect(x: from, y: row.minY, width: to - from, height: row.height) }
        // Where letters are printed along the row, from what each narrow slice of it selects.
        var printed: [(from: CGFloat, to: CGFloat)] = []
        var x = row.minX
        while x < row.maxX {
            let next = min(x + probeStep, row.maxX)
            for piece in page.selection(for: band(x, next)).map({ Self.pieces(of: $0, on: page) }) ?? [] {
                printed.append((piece.bounds.minX, piece.bounds.maxX))
            }
            x = next
        }
        // Letters closer than a space are one word.
        var stretches: [(from: CGFloat, to: CGFloat)] = []
        for letter in printed.sorted(by: { $0.from < $1.from }) {
            if let last = stretches.last, letter.from - last.to <= wordGapRatio * row.height {
                stretches[stretches.count - 1].to = max(last.to, letter.to)
            } else {
                stretches.append(letter)
            }
        }
        let pieces = stretches.flatMap { stretch in page.selection(for: band(stretch.from, stretch.to)).map { Self.pieces(of: $0, on: page) } ?? [] }
        func spelled(_ texts: [String]) -> [Character] { texts.joined().filter { !$0.isWhitespace }.sorted() }
        guard spelled(pieces.map(\.text)) == spelled(runs.map(\.text)) else { return runs }
        return pieces
    }

    // MARK: - Where on the page

    /// A rectangle in page space as the page is shown: normalized 0…1, origin at the
    /// top-left, the page's own turn applied.
    static func box(of rect: CGRect, on page: PDFPage, area: CGRect) -> TextBox {
        let turns = ((page.rotation % 360) + 360) % 360 / 90
        // A point as shown, in points from the shown page's top-left.
        func shown(_ point: CGPoint) -> CGPoint {
            switch turns {
            case 1: CGPoint(x: point.y - area.minY, y: point.x - area.minX)
            case 2: CGPoint(x: area.maxX - point.x, y: point.y - area.minY)
            case 3: CGPoint(x: area.maxY - point.y, y: area.maxX - point.x)
            default: CGPoint(x: point.x - area.minX, y: area.maxY - point.y)
            }
        }
        let size = turns % 2 == 1 ? CGSize(width: area.height, height: area.width) : area.size
        let a = shown(CGPoint(x: rect.minX, y: rect.minY)), b = shown(CGPoint(x: rect.maxX, y: rect.maxY))
        return TextBox(x: Double(min(a.x, b.x) / size.width), y: Double(min(a.y, b.y) / size.height),
                       width: Double(abs(a.x - b.x) / size.width), height: Double(abs(a.y - b.y) / size.height))
    }
}
