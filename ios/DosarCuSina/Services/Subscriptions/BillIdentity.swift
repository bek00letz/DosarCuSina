import Foundation

/// What makes a bill the same bill, whichever photo or PDF of it is filed: the one rule the
/// review, the filing plan, the filer and the repair list use.
///
/// A bill is known within its subscription (the provider and the contract, which
/// `SubscriptionMatcher` already decided):
/// - by its invoice number, when both bills have one: the same number is the same bill,
///   a different number is another bill, even on the same day for the same amount;
/// - else by its issue day and its total together: a bill without a number read on it is the
///   same as one with the same day and the same amount, in the same currency.
/// A bill with neither a number nor a total is never taken for another.
public struct BillIdentity: Hashable, Sendable {
    /// The invoice number as printed ("EXM 0000001"); nil when it wasn't read.
    public var number: String?
    /// The day the bill was issued (else the day it was filed: `CaptureFiler.billDay`).
    public var day: CalendarDay
    /// What the bill came to.
    public var total: Money?

    public init(number: String?, day: CalendarDay, total: Money?) {
        self.number = number
        self.day = day
        self.total = total
    }

    /// How two bills were found to be the same one.
    public enum Match: Hashable, Sendable {
        /// The same invoice number: certain.
        case number
        /// No number on one of them, but the same day and total: very likely, and the review
        /// lets the person say it's another bill.
        case dayAndTotal
    }

    /// Whether `other` is this same bill, and how that is known; nil when it is another bill.
    public func match(_ other: BillIdentity) -> Match? {
        if let mine = Self.comparable(number), let theirs = Self.comparable(other.number) {
            return mine == theirs ? .number : nil
        }
        guard let total, let otherTotal = other.total, total == otherTotal, day == other.day else { return nil }
        return .dayAndTotal
    }

    /// The bill among `bills` that this one is, by the rule above: one with the same number
    /// first, else one with the same day and total. `identity` reads each candidate.
    public func filed<Bill>(among bills: [Bill], identity: (Bill) -> BillIdentity) -> (bill: Bill, match: Match)? {
        let matches = bills.compactMap { bill in match(identity(bill)).map { (bill: bill, match: $0) } }
        return matches.first { $0.match == .number } ?? matches.first
    }

    /// The number as compared: letters and digits only, in capitals ("EXM-0000001" and
    /// "exm 0000001" are the same); nil when nothing is left.
    static func comparable(_ number: String?) -> String? {
        guard let number else { return nil }
        let folded = RomanianText.fold(number).uppercased().filter { $0.isLetter || $0.isNumber }
        return folded.isEmpty ? nil : folded
    }
}

extension BillIdentity {
    /// A bill already logged in a subscription's history, as the rule reads it.
    @MainActor
    public init(entry: HistoryEntry, calendar: Calendar = .current) {
        self.init(number: entry.reference, day: CalendarDay(entry.occurredAt, calendar: calendar), total: entry.totalCost)
    }

    /// The bills logged in a subscription's history: what capture logged, never the "paid"
    /// records completing a deadline writes (as `BillHistory.bills(of:)` reads them).
    @MainActor
    public static func bills(of subscription: Asset) -> [HistoryEntry] {
        (subscription.history ?? []).filter { !$0.isDeleted && $0.kind == .payment && !$0.isCompletion }
    }
}
