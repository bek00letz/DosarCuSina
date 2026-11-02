import Foundation

/// Where a recognized line sits on its page: normalized 0…1, origin at the
/// top-left, y growing downwards, so the geometry reads like the page itself.
public struct TextBox: Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { x }
    public var maxX: Double { x + width }
    public var minY: Double { y }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }

    public func union(_ other: TextBox) -> TextBox {
        let left = min(minX, other.minX), top = min(minY, other.minY)
        return TextBox(x: left, y: top, width: max(maxX, other.maxX) - left, height: max(maxY, other.maxY) - top)
    }

    /// How much the two boxes share horizontally, in page units (0 when apart).
    public func horizontalOverlap(_ other: TextBox) -> Double {
        max(0, min(maxX, other.maxX) - max(minX, other.minX))
    }

    /// How much the two boxes share vertically, in page units (0 when apart).
    public func verticalOverlap(_ other: TextBox) -> Double {
        max(0, min(maxY, other.maxY) - max(minY, other.minY))
    }

    /// Two boxes sit on one row when they share at least half of the smaller one's height.
    public func isOnSameRow(as other: TextBox) -> Bool {
        verticalOverlap(other) >= 0.5 * min(height, other.height)
    }

    /// The horizontal slice of this box that characters `start..<end` of `count` cover,
    /// for finding where a label sits inside a longer line.
    func slice(from start: Int, to end: Int, of count: Int) -> TextBox {
        guard count > 0 else { return self }
        let from = Double(max(0, min(start, count))) / Double(count)
        let to = Double(max(0, min(end, count))) / Double(count)
        return TextBox(x: x + width * from, y: y, width: max(width * (to - from), 0), height: height)
    }
}

/// One recognized line, with where it sits on its page when recognition knows.
public struct RecognizedLine: Hashable, Sendable {
    public var text: String
    /// Nil for text that has no position (pasted text, a PDF's text layer, the MRZ).
    public var box: TextBox?

    public init(_ text: String, box: TextBox? = nil) {
        self.text = text
        self.box = box
    }
}

/// Puts recognized fragments in reading order and joins the ones that belong together.
///
/// Recognition returns fragments, not lines: a date printed "03 07 1983" can come
/// back as three pieces. Fragments are grouped into rows (they share at least half
/// of their height), rows go top to bottom, fragments left to right, and fragments
/// on a row closer than the text's own height are one line. The threshold scales
/// with the text, so it works for a card's small print and an invoice's large type.
enum TextLayout {

    /// The largest gap between two fragments of one line, as a multiple of the text height.
    static let mergeGapRatio = 1.0

    /// Lines in reading order with close fragments merged. Lines without a position keep
    /// their order and follow the positioned ones.
    static func arrange(_ lines: [RecognizedLine]) -> [RecognizedLine] {
        let positioned = lines.filter { $0.box != nil }
        let loose = lines.filter { $0.box == nil }
        return rows(positioned).flatMap(merged) + loose
    }

    /// Positioned lines grouped into rows, top to bottom, each row left to right.
    static func rows(_ lines: [RecognizedLine]) -> [[RecognizedLine]] {
        let sorted = lines.sorted { lhs, rhs in
            guard let a = lhs.box, let b = rhs.box else { return false }
            return (a.minY, a.minX) < (b.minY, b.minX)
        }
        var rows: [(anchor: TextBox, lines: [RecognizedLine])] = []
        for line in sorted {
            guard let box = line.box else { continue }
            // The row whose first fragment shares the most height with this one.
            let best = rows.indices
                .filter { rows[$0].anchor.isOnSameRow(as: box) }
                .max { rows[$0].anchor.verticalOverlap(box) < rows[$1].anchor.verticalOverlap(box) }
            if let best {
                rows[best].lines.append(line)
            } else {
                rows.append((box, [line]))
            }
        }
        return rows
            .sorted { $0.anchor.minY < $1.anchor.minY }
            .map { row in row.lines.sorted { ($0.box?.minX ?? 0) < ($1.box?.minX ?? 0) } }
    }

    /// One row with neighbouring fragments joined, left to right.
    static func merged(_ row: [RecognizedLine]) -> [RecognizedLine] {
        var result: [RecognizedLine] = []
        for line in row {
            guard let box = line.box, let last = result.last, let lastBox = last.box else {
                result.append(line)
                continue
            }
            let gap = box.minX - lastBox.maxX
            let height = min(box.height, lastBox.height)
            if gap <= mergeGapRatio * height, gap >= -0.5 * height {
                result[result.count - 1] = RecognizedLine(last.text + " " + line.text, box: lastBox.union(box))
            } else {
                result.append(line)
            }
        }
        return result
    }
}
