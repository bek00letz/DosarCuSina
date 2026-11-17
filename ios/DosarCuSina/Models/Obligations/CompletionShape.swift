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

        /// Its name, the header above the photo: „Raportul ITP”.
        public var name: String
        public var gender: Gender
        public var use: Use
        /// The card that asks for the photo: „Fotografiază raportul ITP”.
        public var action: String
        /// Under the card, which paper is meant: „Cel primit la stație, cu data următoarei inspecții.”
        public var example: String

        public init(name: String, gender: Gender, use: Use, action: String, example: String) {
            self.name = name
            self.gender = gender
            self.use = use
            self.action = action
            self.example = example
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

    /// A section that closing replaces with a new one of its own (a personal document: a new
    /// identity card or passport has another series and number, so it is a new upload, never a
    /// new date on the old one). Closing asks no new end; the deadline closes, the section's
    /// page shows it expired (`Asset.wasReplaced`) and offers the new one and deleting this
    /// one, in these words, which `docs/COPY_MATRIX.md` lists.
    public struct Replacement: Hashable, Sendable {
        /// In "Am rezolvat", under what it asks: what saving does and where the new one goes.
        public var inSheet: String
        /// The card's title on the section's page and the deadline's, once it is closed.
        public var title: String
        /// Under the title: why the new one is added on its own.
        public var message: String
        /// Adds the new one, for the same holder.
        public var add: String
        /// Deletes this one, with its undo.
        public var delete: String
        /// The toast's offer after closing it: opens this section's page.
        public var open: String

        public init(inSheet: String, title: String, message: String, add: String, delete: String, open: String) {
            self.inSheet = inSheet
            self.title = title
            self.message = message
            self.add = add
            self.delete = delete
            self.open = open
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
    /// The section closing it replaces with a new one; nil for every other kind.
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
    /// Whether closing it replaces its section with a new one (`Replacement`).
    public var replacesSection: Bool { replacement != nil }

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
