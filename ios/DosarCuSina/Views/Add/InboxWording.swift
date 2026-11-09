import Foundation

/// How an item from another app reads in De verificat, so two PDFs shared one after the
/// other can be told apart. The one place that decides a row's words; pure, so tested.
///
/// - **Title:** what it is, once the phone has read it ("Factură ENGIE Romania S.A.",
///   "Poliță RCA 2026", "Carte de identitate"); before that, the file's own name without
///   its extension and the noise apps add ("IMG_2041", "WhatsApp Image … at …", "(1)");
///   else the app it came from when its name says so ("Poză din WhatsApp"); else what it
///   is made of ("Un PDF", "O poză", "Poze", "Un text").
/// - **Line under it:** the file's name when the title is the reading, the pages ("3
///   pagini") and when it arrived.
/// - **Nothing that may not be shown:** every name goes through `SearchPrivacy.outsideText`
///   (no CNP, no card number, no sealed value). While a section lock is closed, an item
///   read as belonging to a locked category is only "Act protejat", with no name, no
///   picture and no file name, and an item not read yet names nothing either.
enum InboxWording {
    /// What one row shows.
    struct Row: Equatable {
        var title: String
        var detail: String
        var symbol: String
        /// The first page's picture may be drawn.
        var showsThumbnail: Bool
        /// It belongs to a locked category: opening it asks to unlock first.
        var isProtected: Bool
    }

    /// The row for an item.
    /// - Parameters:
    ///   - lockedCategories: the keys of the categories behind Face ID (`CategoryTemplate.isSensitive`).
    ///   - isSessionUnlocked: the unlock session is open, so locked categories show.
    static func row(
        for item: InboxItem,
        preview: InboxPreview?,
        lockedCategories: Set<String>,
        isSessionUnlocked: Bool,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Row {
        let received = received(item.receivedAt, now: now, calendar: calendar)
        let pageCount = preview?.pageCount ?? (item.payload == .images ? item.files.count : 1)
        let pages = pageCount > 1 ? String(localized: "\(pageCount) pagini", comment: "How many pages a document shared from another app has: „3 pagini”. Only shown for two or more.") : nil
        let isClosed = !isSessionUnlocked && !lockedCategories.isEmpty

        if isClosed, let key = preview?.categoryKey, lockedCategories.contains(key) {
            return Row(title: String(localized: "Act protejat", comment: "De verificat: something shared that belongs to a locked section; nothing about it shows until unlock."),
                       detail: joined([pages, received]), symbol: "lock.fill", showsThumbnail: false, isProtected: true)
        }
        if item.isPractice {
            return Row(title: String(localized: "Factură de probă"), detail: joined([pages, received]), symbol: symbol(item), showsThumbnail: preview?.hasThumbnail == true, isProtected: false)
        }
        // Not read yet while a lock is closed: it might be a locked category's, so it names nothing.
        if isClosed, preview == nil {
            return Row(title: madeOf(item, sender: nil), detail: joined([pages, received]), symbol: symbol(item), showsThumbnail: false, isProtected: false)
        }

        let name = cleanedName(item.originalName)
        let sender = sender(of: item.originalName)
        if let reading = preview?.title {
            let origin = name ?? sender.map { String(localized: "Din \($0)", comment: "De verificat: the app a file came from, e.g. „Din WhatsApp”.") }
            let shownOrigin = origin.flatMap { RomanianText.fold($0) == RomanianText.fold(reading) ? nil : $0 }
            return Row(title: reading, detail: joined([shownOrigin, pages, received]), symbol: symbol(item), showsThumbnail: preview?.hasThumbnail == true, isProtected: false)
        }
        return Row(title: name ?? madeOf(item, sender: sender), detail: joined([pages, received]), symbol: symbol(item),
                   showsThumbnail: preview?.hasThumbnail == true, isProtected: false)
    }

    /// The short title used in the toast after a dismissal ("Am scos „…” din De verificat.").
    static func title(_ item: InboxItem, preview: InboxPreview?, lockedCategories: Set<String>, isSessionUnlocked: Bool) -> String {
        row(for: item, preview: preview, lockedCategories: lockedCategories, isSessionUnlocked: isSessionUnlocked).title
    }

    // MARK: Names

    /// A file's name as a person would say it: no extension, no copy marks, no runs of
    /// underscores, nothing that may not be shown. Nil when what is left is only what a
    /// camera or an app made up ("IMG_2041", "WhatsApp Image 2026-11-02 at 10.15.32",
    /// "document (1)", "Scan 2 nov. 2026").
    static func cleanedName(_ name: String?) -> String? {
        guard var text = name?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        let ext = (text as NSString).pathExtension
        if !ext.isEmpty, ext.count <= 5, ext.allSatisfy({ $0.isLetter || $0.isNumber }) {
            text = (text as NSString).deletingPathExtension
        }
        // "factura_engie__oct" reads "factura engie oct"; a copy's "(1)" or " copy" goes.
        text = text.replacingOccurrences(of: "[_]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\s*\\(\\d+\\)$", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)[ -](copy|copie)( \\d+)?$", with: "", options: .regularExpression)
        text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard let shown = SearchPrivacy.outsideText(text), !isNoise(shown) else { return nil }
        return shown
    }

    /// The app a file came from, when its name says so. Only WhatsApp names its files in a
    /// way that can't be mistaken ("WhatsApp Image …", "IMG-20261102-WA0001").
    static func sender(of name: String?) -> String? {
        guard let name else { return nil }
        let folded = RomanianText.fold(name)
        if folded.hasPrefix("whatsapp ") || name.range(of: "-WA[0-9]{4}", options: .regularExpression) != nil { return "WhatsApp" }
        return nil
    }

    /// Words cameras, scanners and apps name files with, which say nothing about the paper.
    static let noiseWords: Set<String> = [
        "img", "image", "imagine", "photo", "poza", "foto", "pic", "picture", "pxl", "dsc", "dscn", "dcim", "mvimg", "pano",
        "screenshot", "screen", "shot", "captura", "ecran", "scan", "scanned", "scanat", "scanare", "document", "documente",
        "doc", "file", "fisier", "attachment", "atasament", "untitled", "fara", "titlu", "whatsapp", "wa", "at", "la", "de",
        "pdf", "jpg", "jpeg", "heic", "png", "new", "nou", "copy", "copie",
    ]

    /// Only made-up words, numbers, dates and times: nothing a person chose.
    static func isNoise(_ text: String) -> Bool {
        let words = RomanianText.fold(text)
            .split { !($0.isLetter || $0.isNumber) }
            .map(String.init)
            // Dates, times, counters and the camera's own "IMG-20261102-WA0001" pieces.
            .filter { word in !word.allSatisfy(\.isNumber) && word.range(of: "^(wa|img|pxl|dsc|vid)?[0-9]+$", options: .regularExpression) == nil }
        // A long run of letters and digits with no vowel pattern (a hash, a UUID) is noise too.
        let meaningful = words.filter { !noiseWords.contains($0) && !looksGenerated($0) }
        return meaningful.isEmpty
    }

    private static let monthWords: Set<String> = [
        "ian", "feb", "mar", "apr", "mai", "iun", "iul", "aug", "sep", "sept", "oct", "noi", "nov", "dec",
        "jan", "jun", "jul",
    ]

    private static func looksGenerated(_ word: String) -> Bool {
        if monthWords.contains(word) { return true }
        // Mostly digits mixed with letters, long: "3f2a9c1e", "a1b2c3d4e5".
        let digits = word.filter(\.isNumber).count
        return word.count >= 8 && digits * 3 >= word.count
    }

    // MARK: Parts

    /// What it is made of, when nothing better is known: "Un PDF", "O poză", "Poze", "Un text",
    /// or with the app it came from: "Un PDF din WhatsApp".
    static func madeOf(_ item: InboxItem, sender: String?) -> String {
        let what = switch item.payload {
        // Not a count: no number is shown (the line under it says "3 pagini"), so one photo
        // and several are two strings of their own, as the String Catalog asks.
        case .images where item.files.count > 1: String(localized: "Poze", comment: "De verificat: several photos shared together, read as the pages of one document.")
        case .images: String(localized: "O poză", comment: "De verificat: one photo shared from another app.")
        case .pdf: String(localized: "Un PDF")
        case .text: String(localized: "Un text")
        }
        guard let sender else { return what }
        return String(localized: "\(what) din \(sender)", comment: "De verificat: what was shared and the app it came from, e.g. „Un PDF din WhatsApp”, „Poze din WhatsApp”.")
    }

    static func symbol(_ item: InboxItem) -> String {
        switch item.payload {
        case .images: return "photo"
        case .pdf: return "doc.richtext"
        case .text: return "text.alignleft"
        }
    }

    static func received(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let time = DosarFormat.time(date, calendar: calendar)
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "Primit azi la \(time)") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "Primit ieri la \(time)")
        }
        let day = DosarFormat.dayMonth(date, calendar: calendar)
        return String(localized: "Primit pe \(day)")
    }

    private static func joined(_ parts: [String?]) -> String {
        parts.compactMap { $0 }.joined(separator: " · ")
    }
}
