import Foundation

/// A point on a page as fractions of its width and height, from its top-left corner.
/// Fractions, not pixels, so a crop stays right when the page is kept smaller.
public struct PagePoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// What the person chose for one page. It wins over what the app guessed, whatever a
/// later reading guesses.
public struct PageChoice: Codable, Hashable, Sendable {
    /// Quarter turns clockwise, as the person left the page (0 to 3).
    public var quarterTurns: Int?
    /// The whole photo instead of the document cut out of it ("Folosește poza întreagă"),
    /// or, false, the cut-out again.
    public var showsWholePhoto: Bool?

    public init(quarterTurns: Int? = nil, showsWholePhoto: Bool? = nil) {
        self.quarterTurns = quarterTurns
        self.showsWholePhoto = showsWholePhoto
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        quarterTurns = try container.decodeIfPresent(Int.self, forKey: .quarterTurns)
        showsWholePhoto = try container.decodeIfPresent(Bool.self, forKey: .showsWholePhoto)
    }

    var isEmpty: Bool { quarterTurns == nil && showsWholePhoto == nil }
}

/// How one page of a document is shown, shared and read: the document found in the photo,
/// and which way up it goes. The photo as taken is always what is kept; this only says
/// how to draw it, so going back to the whole photo loses nothing.
public struct PageFraming: Codable, Hashable, Sendable {
    /// The document's corners in the photo as taken: top-left, top-right, bottom-right,
    /// bottom-left. Nil when no document was found, or the page isn't a photo (a scan, a PDF).
    public var crop: [PagePoint]?
    /// The app's guess that the whole photo reads better than the document cut out of it.
    public var prefersWholePhoto: Bool
    /// The app's guess: the quarter turns clockwise that put the page upright.
    public var quarterTurns: Int
    /// What the person chose; it wins over both guesses.
    public var choice: PageChoice?

    public init(crop: [PagePoint]? = nil, prefersWholePhoto: Bool = false, quarterTurns: Int = 0, choice: PageChoice? = nil) {
        self.crop = crop
        self.prefersWholePhoto = prefersWholePhoto
        self.quarterTurns = Self.normalized(quarterTurns)
        self.choice = choice
    }

    /// Unknown or missing keys (a newer or older version) read as the plain page.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let corners = try container.decodeIfPresent([PagePoint].self, forKey: .crop)
        crop = corners?.count == 4 ? corners : nil
        prefersWholePhoto = try container.decodeIfPresent(Bool.self, forKey: .prefersWholePhoto) ?? false
        quarterTurns = Self.normalized(try container.decodeIfPresent(Int.self, forKey: .quarterTurns) ?? 0)
        let choice = try container.decodeIfPresent(PageChoice.self, forKey: .choice)
        self.choice = choice?.isEmpty == true ? nil : choice
    }

    /// The page as it came: the whole picture, upright as given.
    public static let plain = PageFraming()

    /// A document was found in the photo, so it can be shown cut out or whole.
    public var hasCrop: Bool { crop?.count == 4 }

    /// The page is drawn cut out of the photo: a crop was found, and neither the person
    /// nor the reading chose the whole photo.
    public var showsCrop: Bool {
        hasCrop && !(choice?.showsWholePhoto ?? prefersWholePhoto)
    }

    /// The quarter turns clockwise the page is drawn with: the person's, else the guess.
    public var shownQuarterTurns: Int {
        Self.normalized(choice?.quarterTurns ?? quarterTurns)
    }

    /// The person turned the page a quarter turn clockwise (or `turns` of them) from how it is shown.
    public func turned(by turns: Int = 1) -> PageFraming {
        var framing = self
        var choice = framing.choice ?? PageChoice()
        choice.quarterTurns = Self.normalized(shownQuarterTurns + turns)
        framing.choice = choice
        return framing
    }

    /// The person chose the whole photo, or the document cut out of it again.
    public func showingWholePhoto(_ whole: Bool) -> PageFraming {
        var framing = self
        var choice = framing.choice ?? PageChoice()
        choice.showsWholePhoto = whole
        framing.choice = choice
        return framing
    }

    /// The person's choice on top of this page's guesses: their turn and their crop choice win.
    public func applying(_ choice: PageChoice?) -> PageFraming {
        guard let choice, !choice.isEmpty else { return self }
        var framing = self
        var merged = framing.choice ?? PageChoice()
        if let turns = choice.quarterTurns { merged.quarterTurns = Self.normalized(turns) }
        if let whole = choice.showsWholePhoto { merged.showsWholePhoto = whole }
        framing.choice = merged
        return framing
    }

    /// 0 to 3, whatever the count (a negative one turns the other way).
    public static func normalized(_ turns: Int) -> Int {
        ((turns % 4) + 4) % 4
    }

    var isPlain: Bool {
        crop == nil && !prefersWholePhoto && quarterTurns == 0 && (choice?.isEmpty ?? true)
    }
}

/// How every page of a document is shown: kept on the document (`Attachment.framing`),
/// written to backups, and read by everything that draws, shares or reads a page
/// (`DocumentPicture`). Page `n` is the document's `n`-th page image, or a PDF's `n`-th page.
public struct DocumentFraming: Codable, Hashable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var pages: [PageFraming]

    public init(pages: [PageFraming] = []) {
        self.version = Self.currentVersion
        self.pages = pages
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        pages = try container.decodeIfPresent([PageFraming].self, forKey: .pages) ?? []
    }

    /// How page `index` is shown; a page nothing was said about is shown as it came.
    public subscript(page index: Int) -> PageFraming {
        get { pages.indices.contains(index) ? pages[index] : .plain }
        set {
            guard index >= 0 else { return }
            while pages.count <= index { pages.append(.plain) }
            pages[index] = newValue
        }
    }

    /// The person's choices on top of these guesses, page by page.
    public func applying(_ choices: [Int: PageChoice]) -> DocumentFraming {
        var framing = self
        for (index, choice) in choices where index >= 0 {
            framing[page: index] = framing[page: index].applying(choice)
        }
        return framing
    }

    /// Nothing to keep: every page is shown as it came.
    public var isPlain: Bool { pages.allSatisfy(\.isPlain) }
}

extension Attachment {
    /// How the document's pages are shown, shared and read. A document from before
    /// version 6, or one nothing was decided about, shows its pages as they are.
    public var framing: DocumentFraming {
        get { StoredJSON.decode(DocumentFraming.self, from: framingData) ?? DocumentFraming() }
        set { framingData = newValue.isPlain ? nil : StoredJSON.encode(newValue) }
    }
}
