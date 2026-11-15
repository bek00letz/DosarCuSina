import Foundation

/// What closing a deadline in the app asks, by its kind: the one place that says it. A chore
/// asks nothing ("Gata" marks it done today, a note offered after); a payment asks what was
/// paid and the bill; a renewal the new document and when it expires; and so on. Read by every
/// screen that completes a deadline (the deadline's page, Urmează) and by what saving keeps
/// (`CompletionDraft`), so a value a kind doesn't ask is never written.
///
/// Outside the app (a reminder's button, the widget's *Gata*, Siri) every kind completes in
/// one step, as before (`IntentEngine`): nothing there can ask.
public struct CompletionShape: Hashable, Sendable {
    /// The question for the money a completion cost.
    public enum Cost: Hashable, Sendable {
        /// "Cât a costat": a job, a check, a policy.
        case cost
        /// "Cât ai plătit": a bill or a tax, where the amount is the point.
        case paid
    }

    /// The paper a completion keeps, which says how the sheet asks for it. Every one is read by
    /// the same capture and filed by the same filer (`CaptureFiler.Completion`): a bill on its
    /// subscription as a bill, a new document's date as the next deadline.
    public enum Paper: String, Hashable, Sendable, CaseIterable {
        /// A service's or a firm's invoice for the job.
        case invoice
        /// The bill being paid.
        case bill
        /// The renewed document itself (an identity card, a passport, a contract).
        case newDocument
        /// The new insurance policy.
        case policy
        /// What proves a legal check was done (an ITP report, a gas check, a rovinietă).
        case certificate
        /// The receipt or the proof of payment of a tax.
        case receipt
        /// A medical result, a prescription or the vaccination booklet.
        case result
    }

    /// The day it was done ("Când"), today unless the person says otherwise.
    public var asksDate: Bool
    /// What it cost, and how the question is put; nil when it isn't asked.
    public var cost: Cost?
    /// The paper it keeps; nil when none is asked for.
    public var paper: Paper?
    /// The day the renewed document expires, read from its photo or typed.
    public var asksNewExpiry: Bool
    /// A note, in the sheet ("Ce a spus medicul").
    public var asksNote: Bool
    /// The section's counter (a car's kilometres), where it has one.
    public var asksReading: Bool

    public init(asksDate: Bool = true, cost: Cost? = nil, paper: Paper? = nil, asksNewExpiry: Bool = false,
                asksNote: Bool = false, asksReading: Bool = false) {
        self.asksDate = asksDate
        self.cost = cost
        self.paper = paper
        self.asksNewExpiry = asksNewExpiry
        self.asksNote = asksNote
        self.asksReading = asksReading
    }

    /// Nothing to ask: done today in one tap.
    public static let oneTap = CompletionShape(asksDate: false)

    /// Whether completing asks nothing: "Gata" marks it done today, no sheet, and its toast
    /// offers a note for that completion ("Adaugă o notă").
    public var isOneTap: Bool {
        !asksDate && cost == nil && paper == nil && !asksNewExpiry && !asksNote && !asksReading
    }

    /// Whether the toast of a completion offers a note after it.
    public var offersNoteAfter: Bool { isOneTap }

    /// The way back: off, every kind asks what "Am rezolvat" asked before (when, the cost, a
    /// photo of the new document), until the owner has used the shapes. Remove with
    /// `everyKindBefore` once the owner agrees.
    static let asksByKind = true

    /// What "Am rezolvat" asked of every kind before the shapes.
    static let everyKindBefore = CompletionShape(cost: .cost, paper: .newDocument)
}

extension ObligationKind {
    /// What completing a deadline of this kind asks in the app. See `CompletionShape`.
    public var completion: CompletionShape {
        guard CompletionShape.asksByKind else { return CompletionShape.everyKindBefore }
        return switch self {
        // A chore: "Doar să nu uit". Done today, in one tap.
        case .routine:
            .oneTap
        // Upkeep: when, what it cost, the service's invoice, and the counter where the section has one.
        case .maintenance:
            CompletionShape(cost: .cost, paper: .invoice, asksReading: true)
        // A bill: what was paid and the bill itself, filed as a bill.
        case .payment:
            CompletionShape(cost: .paid, paper: .bill)
        // A document that expires: the new one, and when it expires.
        case .renewal:
            CompletionShape(paper: .newDocument, asksNewExpiry: true)
        // A legal check (ITP, gas installation, rovinietă): when, its fee, and the proof.
        case .legal:
            CompletionShape(cost: .cost, paper: .certificate)
        // Insurance: the new policy, whose dates and numbers fill the section, and its price.
        case .insurance:
            CompletionShape(cost: .cost, paper: .policy)
        // A tax: what was paid and the receipt.
        case .tax:
            CompletionShape(cost: .paid, paper: .receipt)
        // Health: when, a note on how it went, the result; a vet or a dentist costs.
        case .health:
            CompletionShape(cost: .cost, paper: .result, asksNote: true)
        }
    }
}
