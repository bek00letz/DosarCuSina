import Foundation

/// What makes a paper the same paper, whichever photo or PDF of it is filed: a bill in its
/// subscription, a visit's, a repair's or a purchase's invoice on its section. The one rule
/// the review, the filing plan, the visit form, the filer and the repair list use.
///
/// A paper is known within the section it belongs to (a bill's subscription, which
/// `SubscriptionMatcher` already decided; the car or the pet a visit is on):
/// - by its number, when both papers have one. A different number is another paper, even on
///   the same day for the same amount. The same number is the same paper for certain only
///   when it can only be one issuer's: a bill's, whose subscription is its provider, or an
///   invoice from the same firm on the same day. Firms number their own invoices, and many
///   start again each year, so the same number from another firm is another paper; with a
///   firm on one of them only, or on another day, it may be the same paper or another, and
///   the person can say which ("E altă factură").
/// - else by its day and its total together, in the same currency, and by who issued it
///   when both name someone: the same day and total from another firm is another invoice.
/// A paper with neither a number nor a total is never taken for another.
public struct PaperIdentity: Hashable, Sendable {
    /// The number as printed ("EXM 0000001"); nil when it wasn't read.
    public var number: String?
    /// The day it was issued (a bill's, else the day it was filed: `CaptureFiler.billDay`;
    /// a visit's day).
    public var day: CalendarDay
    /// What it came to.
    public var total: Money?
    /// Who issued it.
    public var issuer: Issuer

    /// Who issued a paper, as far as the rule can tell.
    public enum Issuer: Hashable, Sendable {
        /// The section it is filed in names the issuer: a bill, whose subscription is one
        /// provider's, so its numbers are that provider's.
        case section
        /// Named on the paper or the record (a visit's firm); nil when nobody was named.
        case named(String?)
    }

    /// An invoice, a receipt or a visit's paper, with the firm named on it, if any.
    public init(number: String?, day: CalendarDay, total: Money?, issuer: String? = nil) {
        self.number = number
        self.day = day
        self.total = total
        self.issuer = .named(issuer)
    }

    /// A bill of a subscription: its provider is the subscription's.
    public static func bill(number: String?, day: CalendarDay, total: Money?) -> PaperIdentity {
        var bill = PaperIdentity(number: number, day: day, total: total)
        bill.issuer = .section
        return bill
    }

    /// How two papers were found to be the same one.
    public enum Match: Hashable, Sendable {
        /// The same number, from the same issuer: certain.
        case number
        /// The same number, but nothing to say it is the same issuer's paper (a firm on one
        /// of them only, or another day): likely, and the person can say it's another paper.
        case numberOnly
        /// No number on one of them, but the same day and total (and firm, when both name
        /// one): very likely, and the person can say it's another paper.
        case dayAndTotal
    }

    /// Whether `other` is this same paper, and how that is known; nil when it is another one.
    public func match(_ other: PaperIdentity) -> Match? {
        let firms = Self.firms(issuer, other.issuer)
        if let mine = Self.comparable(number), let theirs = Self.comparable(other.number) {
            guard mine == theirs else { return nil }
            switch firms {
            case .sameSection: return .number
            case .same: return day == other.day ? .number : .numberOnly
            case .different: return nil
            case .unknown: return .numberOnly
            }
        }
        guard let total, let otherTotal = other.total, total == otherTotal, day == other.day else { return nil }
        if firms == .different { return nil }
        return .dayAndTotal
    }

    /// The paper among `papers` that this one is, by the rule above: the most certain match
    /// first (the same number from the same issuer, then the same number alone, then the
    /// same day and total). `identity` reads each candidate.
    public func filed<Paper>(among papers: [Paper], identity: (Paper) -> PaperIdentity) -> (paper: Paper, match: Match)? {
        let matches = papers.compactMap { paper in match(identity(paper)).map { (paper: paper, match: $0) } }
        return matches.first { $0.match == .number } ?? matches.first { $0.match == .numberOnly } ?? matches.first
    }

    /// What the two papers' issuers say about them.
    private enum Firms { case sameSection, same, different, unknown }

    private static func firms(_ one: Issuer, _ other: Issuer) -> Firms {
        switch (one, other) {
        case (.section, .section): return .sameSection
        case (.named(let mine), .named(let theirs)):
            guard let mine = comparable(mine), let theirs = comparable(theirs) else { return .unknown }
            return mine == theirs ? .same : .different
        default: return .unknown
        }
    }

    /// A number or a name as compared: letters and digits only, folded, in capitals
    /// ("EXM-0000001" and "exm 0000001" are the same, so are "Service Exemplu S.R.L." and
    /// "SERVICE EXEMPLU SRL"); nil when nothing is left.
    static func comparable(_ text: String?) -> String? {
        guard let text else { return nil }
        let folded = RomanianText.fold(text).uppercased().filter { $0.isLetter || $0.isNumber }
        return folded.isEmpty ? nil : folded
    }
}

extension PaperIdentity {
    /// A paper already logged in a section's history, as the rule reads it: its number, its
    /// day, its total and who issued it (a bill's subscription, a visit's firm).
    @MainActor
    public init(entry: HistoryEntry, calendar: Calendar = .dosar) {
        self.init(number: entry.reference, day: CalendarDay(entry.occurredAt, calendar: calendar), total: entry.totalCost,
                  issuer: entry.providerNames.first)
        if entry.kind == .payment { issuer = .section }
    }

    /// The bills logged in a subscription's history: what capture logged, never the "paid"
    /// records completing a deadline writes (as `BillHistory.bills(of:)` reads them).
    @MainActor
    public static func bills(of subscription: Asset) -> [HistoryEntry] {
        (subscription.history ?? []).filter { !$0.isDeleted && $0.kind == .payment && !$0.isCompletion }
    }

    /// The visits, repairs and purchases logged in a section's history, whose invoice another
    /// photo may be: never a bill, and never a record a deadline's completion wrote.
    @MainActor
    public static func visits(of section: Asset) -> [HistoryEntry] {
        (section.history ?? []).filter { !$0.isDeleted && $0.kind != .payment && !$0.isCompletion }
    }

    /// The entry a paper being filed is already logged as, in one order for every paper:
    /// the entry its own document is filed with (`keptDocumentEntry`, the same photo or file
    /// filed again, which the caller finds where that paper's document may be), else the
    /// entry among `entries` the rule finds for `paper` (another photo or PDF of it). `paper`
    /// is nil when there is nothing to compare: no document, or the person said it is another
    /// paper ("E altă factură").
    @MainActor
    static func filed(keptDocumentEntry: HistoryEntry?, paper: PaperIdentity?, among entries: [HistoryEntry],
                      calendar: Calendar) -> (entry: HistoryEntry, paper: FiledPaper)? {
        if let kept = keptDocumentEntry, !kept.isDeleted {
            return (kept, FiledPaper(kept, match: .sameDocument, calendar: calendar))
        }
        guard let paper, let found = paper.filed(among: entries, identity: { PaperIdentity(entry: $0, calendar: calendar) }) else { return nil }
        return (found.paper, FiledPaper(found.paper, match: FiledPaper.Match(found.match), calendar: calendar))
    }
}

/// A paper being filed that is already in the binder: the same document filed again, or
/// another photo or PDF of the same paper (`PaperIdentity`). Saving updates its entry instead
/// of logging a second one, and a new photo becomes its newer copy
/// (`AttachmentActions.keepAsNewerCopy`). The review shows it for a bill, the visit form for
/// an invoice, "Am rezolvat" for the bill it pays, all with `DSFiledPaperNotice` in the words
/// of `FiledPaperWording`.
struct FiledPaper: Equatable {
    enum Match: Equatable {
        /// The same document (the same photo or file) filed again.
        case sameDocument
        /// The same number from the same issuer in the same section.
        case number
        /// The same number in the same section, nothing more to confirm it.
        case numberOnly
        /// No number to compare, the same day and total (and firm) in the same section.
        case dayAndTotal

        init(_ match: PaperIdentity.Match) {
            switch match {
            case .number: self = .number
            case .numberOnly: self = .numberOnly
            case .dayAndTotal: self = .dayAndTotal
            }
        }
    }

    /// The paper's entry in its section's history.
    var entryID: UUID
    var match: Match
    /// The section the entry is in now (a bill's subscription, a visit's car), and its name.
    var sectionID: UUID?
    var section: String
    /// The day the entry is logged on.
    var day: CalendarDay

    @MainActor
    init(_ entry: HistoryEntry, match: Match, calendar: Calendar) {
        self.entryID = entry.id
        self.match = match
        self.sectionID = entry.asset?.id
        self.section = entry.asset?.name ?? ""
        self.day = CalendarDay(entry.occurredAt, calendar: calendar)
    }

    init(entryID: UUID, match: Match, sectionID: UUID?, section: String, day: CalendarDay) {
        self.entryID = entryID
        self.match = match
        self.sectionID = sectionID
        self.section = section
        self.day = day
    }

    /// Whether the person may say it is another paper ("E altă factură"): when the match
    /// rests on the day and total, or on the number alone. The same document, or the same
    /// number from the same issuer, is certain.
    var mayBeAnother: Bool { match == .dayAndTotal || match == .numberOnly }
}
