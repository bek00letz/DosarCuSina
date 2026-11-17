import Foundation

/// What closing a deadline in the app asks: the day, the money and how it is asked, the paper
/// and its name, a new end date, a note, a counter. Each deadline's blueprint states which
/// (`ObligationBlueprint.completion`, a `CompletionKind`), and each kind is described once
/// (`CompletionKind.shape`): a chore asks nothing ("Gata" marks it done today, a note offered
/// after); a bill asks what was paid and the bill; an ITP the fee and the ITP report; a renewed
/// document the new one and when it expires; and so on. Read by every screen that completes a
/// deadline (the deadline's page, Urmează) and by what saving keeps (`CompletionDraft`), so a
/// value a kind doesn't ask is never written.
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

    /// Which counter a completion asks, where the section keeps one.
    public enum Counter: Hashable, Sendable {
        /// The section's own counter (a car's kilometres, a bike's), whatever the deadline
        /// counts on: work on a vehicle is logged with its reading.
        case section
        /// Only the counter the deadline counts on (descaling every 300 cafele), for work done
        /// at home: one that repeats by time asks none.
        case countedOn
    }

    /// The paper a completion keeps, by its name: „Raportul ITP”, „Polița nouă”, „Carnetul de
    /// sănătate”. Every one is read by the same capture and filed by the same filer
    /// (`CaptureFiler.Completion`): a bill on its subscription as a bill, a paper's date as the
    /// next deadline. Its sentences agree with its noun (`gender`), so „Îl păstrez” never
    /// follows „Chitanța” (`CompletionWording`).
    public struct Paper: Hashable, Sendable {
        /// Which pronoun the paper's noun takes: „îl” and „el” (a report, a card, a contract),
        /// „o” and „ea” (a bill, a policy, a receipt), „le” and „ele” (the results).
        public enum Gender: String, Hashable, Sendable, CaseIterable {
            case masculine
            case feminine
            case plural
        }

        /// What the photo is for, said under the paper's name.
        public enum Use: String, Hashable, Sendable, CaseIterable {
            /// Kept in the binder: „Opțional. O păstrez în dosar.”
            case keep
            /// Kept with the job in Istoric: „Opțional. O păstrez în istoric.”
            case history
            /// The bill, logged in Istoric as a bill: „Opțional. O trec în istoric.”
            case logged
            /// Its next date becomes the deadline's: „Opțional. Din el iau data următoare.”
            case nextDate
            /// The day the new one expires: „Opțional. Din el iau data la care expiră.”
            case expiry
            /// The day the new one ends: „Opțional. Din el iau data la care se termină.”
            case end
        }

        /// How a paper comes from someone, for the words that name them on its record's page.
        public enum Origin: String, Hashable, Sendable, CaseIterable {
            /// Issued by an office or a firm: an identity document, a card, a report. „Cine l-a emis”.
            case issued
            /// Signed with someone: a contract, a lease. „Cu cine l-ai semnat”.
            case signed
        }

        /// Its name, the header above the photo: „Raportul ITP”.
        public var name: String
        public var gender: Gender
        public var use: Use
        /// The card that asks for the photo: „Fotografiază raportul ITP”.
        public var action: String
        /// Under the card, which paper is meant: „Cel primit la stație, cu data următoarei inspecții.”
        public var example: String
        /// How it comes from someone: issued, or signed with them.
        public var origin: Origin

        public init(name: String, gender: Gender, use: Use, action: String, example: String, origin: Origin = .issued) {
            self.name = name
            self.gender = gender
            self.use = use
            self.action = action
            self.example = example
            self.origin = origin
        }
    }

    /// The new end date a completion asks, typed or read off the paper.
    public enum NewEnd: Hashable, Sendable {
        /// A document's or a kit's new expiry: „Expiră pe”.
        case expires
        /// A contract's new end: „Se termină pe”.
        case ends
    }

    /// A note, in the kind's words.
    public struct Note: Hashable, Sendable {
        /// Its example: „Ce a spus medicul, ce urmează.”
        public var prompt: String

        public init(prompt: String) {
            self.prompt = prompt
        }
    }

    /// A document that closing replaces with a new one (a new identity card, passport or
    /// European health card has another series and number, so it is a new upload, never a new
    /// date on the old one). Closing asks no new end and closes the deadline, whatever its repeat
    /// (`ObligationActions.complete`); the page holding the card (`DocumentReplacementCard`)
    /// offers the new one, in these words, which `docs/COPY_MATRIX.md` lists.
    public struct Replacement: Hashable, Sendable {
        /// What the deadline renews.
        public enum Replaces: Hashable, Sendable {
            /// The section itself, a personal document: its page shows it expired
            /// (`Asset.wasReplaced`) and offers deleting it, in `delete`'s words.
            case thisSection(delete: String)
            /// A personal document of the section's person, of `documentType`, that the section
            /// only reminds about (the European health card on a health file): the new one is
            /// added to their documents and the section stays as it is, never shown expired.
            case holdersDocument(documentType: String)
        }

        /// In "Am rezolvat", under what it asks: what saving does and where the new one goes.
        public var inSheet: String
        /// The card's title on the section's page and the deadline's, once it is closed.
        public var title: String
        /// Under the title: why the new one is added on its own.
        public var message: String
        /// Adds the new one, for the same holder.
        public var add: String
        /// The toast's offer after closing it: opens the page that holds the card (the
        /// document's for `thisSection`, the deadline's for `holdersDocument`).
        public var open: String
        public var replaces: Replaces

        public init(inSheet: String, title: String, message: String, add: String, open: String, replaces: Replaces) {
            self.inSheet = inSheet
            self.title = title
            self.message = message
            self.add = add
            self.open = open
            self.replaces = replaces
        }

        /// Deletes the old one, with its undo: only a section that is the document itself.
        public var delete: String? {
            if case .thisSection(let delete) = replaces { return delete }
            return nil
        }

        /// Whether the section itself is the document replaced (`Asset.wasReplaced`).
        public var replacesItsSection: Bool { delete != nil }

        /// The type of the document that replaces it, when it is one of the holder's own
        /// documents and not the section (`holdersDocument`).
        public var holdersDocumentType: String? {
            if case .holdersDocument(let type) = replaces { return type }
            return nil
        }
    }

    /// The day it was done ("Când"), today unless the person says otherwise.
    public var asksDate: Bool
    /// What it cost, and how the question is put; nil when it isn't asked.
    public var cost: Cost?
    /// The paper it keeps; nil when none is asked for.
    public var paper: Paper?
    /// The new end date it asks; nil when none.
    public var newEnd: NewEnd?
    /// The note it asks in the sheet; nil when none.
    public var note: Note?
    /// The counter it asks, where the section has one; nil when none.
    public var counter: Counter?
    /// The document closing it replaces with a new one; nil for every other kind.
    public var replacement: Replacement?

    public init(asksDate: Bool = true, cost: Cost? = nil, paper: Paper? = nil, newEnd: NewEnd? = nil,
                note: Note? = nil, counter: Counter? = nil, replacement: Replacement? = nil) {
        self.asksDate = asksDate
        self.cost = cost
        self.paper = paper
        self.newEnd = newEnd
        self.note = note
        self.counter = counter
        self.replacement = replacement
    }

    /// Nothing to ask: done today in one tap.
    public static let oneTap = CompletionShape(asksDate: false)

    /// Whether it asks the day the renewed thing expires or ends.
    public var asksNewExpiry: Bool { newEnd != nil }
    /// Whether it asks a note in the sheet.
    public var asksNote: Bool { note != nil }
    /// Whether it asks a counter.
    public var asksReading: Bool { counter != nil }
    /// Whether closing it replaces a document with a new one (`Replacement`): it closes the
    /// deadline, whatever its repeat, and offers the new one.
    public var replacesDocument: Bool { replacement != nil }
    /// Whether closing it replaces its section itself, a personal document (`Asset.wasReplaced`).
    public var replacesSection: Bool { replacement?.replacesItsSection ?? false }

    /// Whether completing asks nothing: "Gata" marks it done today, no sheet, and its toast
    /// offers a note for that completion ("Adaugă o notă").
    public var isOneTap: Bool {
        !asksDate && cost == nil && paper == nil && newEnd == nil && note == nil && counter == nil && replacement == nil
    }

    /// Whether the toast of a completion offers a note after it.
    public var offersNoteAfter: Bool { isOneTap }

    /// The first way back: off, every deadline asks what "Am rezolvat" asked before the shapes
    /// (when, the cost, a photo of the new document). Remove with `everyKindBefore` once the
    /// owner agrees.
    static let asksByKind = true

    /// What "Am rezolvat" asked of every deadline before the shapes.
    static var everyKindBefore: CompletionShape {
        CompletionShape(cost: .cost, paper: CompletionKind.newDocument.shape.paper)
    }
}
