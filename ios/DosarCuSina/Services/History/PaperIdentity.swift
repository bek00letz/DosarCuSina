import Foundation

/// What makes a paper the same paper, whichever photo or PDF of it is filed: a bill in its
/// subscription, a visit's, a repair's or a purchase's invoice on its section. The one rule
/// the review, the filing plan, the visit form, the filer and the repair list use.
///
/// A paper is known within the section it belongs to (a bill's subscription, which
/// `SubscriptionMatcher` already decided; the car or the pet a visit is on):
/// - by its number, when both papers have one: the same number is the same paper,
///   a different number is another paper, even on the same day for the same amount;
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
    /// Who issued it, as named: a visit's firm. Nil for a bill, whose subscription already
    /// names its provider, and when nobody was named.
    public var issuer: String?

    public init(number: String?, day: CalendarDay, total: Money?, issuer: String? = nil) {
        self.number = number
        self.day = day
        self.total = total
        self.issuer = issuer
    }

    /// How two papers were found to be the same one.
    public enum Match: Hashable, Sendable {
        /// The same number: certain.
        case number
        /// No number on one of them, but the same day and total (and firm, when both name
        /// one): very likely, and the person can say it's another paper.
        case dayAndTotal
    }

    /// Whether `other` is this same paper, and how that is known; nil when it is another one.
    public func match(_ other: PaperIdentity) -> Match? {
        if let mine = Self.comparable(number), let theirs = Self.comparable(other.number) {
            return mine == theirs ? .number : nil
        }
        guard let total, let otherTotal = other.total, total == otherTotal, day == other.day else { return nil }
        if let mine = Self.comparable(issuer), let theirs = Self.comparable(other.issuer), mine != theirs { return nil }
        return .dayAndTotal
    }

    /// The paper among `papers` that this one is, by the rule above: one with the same number
    /// first, else one with the same day and total. `identity` reads each candidate.
    public func filed<Paper>(among papers: [Paper], identity: (Paper) -> PaperIdentity) -> (paper: Paper, match: Match)? {
        let matches = papers.compactMap { paper in match(identity(paper)).map { (paper: paper, match: $0) } }
        return matches.first { $0.match == .number } ?? matches.first
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
    /// day, its total and the firm that did the work.
    @MainActor
    public init(entry: HistoryEntry, calendar: Calendar = .current) {
        self.init(number: entry.reference, day: CalendarDay(entry.occurredAt, calendar: calendar), total: entry.totalCost,
                  issuer: entry.providerNames.first)
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
}

/// A paper being filed that is already in the binder: the same document filed again, or
/// another photo or PDF of the same paper (`PaperIdentity`). Saving updates its entry instead
/// of logging a second one, and a new photo becomes its newer copy
/// (`AttachmentActions.keepAsNewerCopy`). The review shows it for a bill, the visit form for
/// an invoice, "Am rezolvat" for the bill it pays.
struct FiledPaper: Equatable {
    enum Match: Equatable {
        /// The same document (the same photo or file) filed again.
        case sameDocument
        /// The same number in the same section.
        case number
        /// No number to compare, the same day and total (and firm) in the same section.
        case dayAndTotal

        init(_ match: PaperIdentity.Match) {
            self = match == .number ? .number : .dayAndTotal
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

    /// Whether the person may say it is another paper ("E altă factură"): only when the match
    /// rests on the day and total. The same number or the same document is certain.
    var mayBeAnother: Bool { match == .dayAndTotal }
}
