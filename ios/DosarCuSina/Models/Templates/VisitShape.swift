import Foundation

/// What logging a visit asks, by its kind (`VisitKind.shape`), and every word it says doing it:
/// the one place that says it, as `CompletionShape` says what closing a deadline asks. The visit
/// form (`AddVisitFlow`) holds no words of its own: it lays this shape over the category's parts
/// and counter (`VisitForm`) and draws what that says, with the words every kind shares
/// (`VisitFormWording`). What saving keeps follows it too (`VisitDraft.filing`), so a value a kind
/// doesn't ask is never written. `docs/COPY_MATRIX.md` shows every category's form, generated
/// from here (`CopyMatrixTests`).
public struct VisitShape: Hashable, Sendable {
    /// What the form can ask, as a save requirement names them.
    public enum Field: String, Hashable, Sendable, CaseIterable {
        /// A photo of the paper (`paper`).
        case paper
        /// What was done: the ticked parts and jobs, and the rows of one's own (`work`).
        case work
        /// A note (`note`).
        case note
        /// The section's counter (`asksCounter`).
        case counter
        /// What it cost (always asked).
        case cost
        /// Who did it (`provider`).
        case provider
    }

    /// The paper the form asks for, which says how it is named.
    public enum Paper: String, Hashable, Sendable, CaseIterable {
        /// The invoice of a service, a tradesperson or a repair shop.
        case invoice
        /// A doctor's papers: the prescription, the results, the referral.
        case medical
        /// A vet's papers: the record, the prescription, the vaccination booklet.
        case veterinary
    }

    /// What the rows add up to is called, under the money field.
    public enum Sum: Hashable, Sendable {
        /// „Piesele adună …”: a vehicle's parts.
        case parts
        /// „Rândurile adună …”.
        case rows
    }

    /// The words of what was done.
    public struct WorkWords: Hashable, Sendable {
        /// Above the checklist: „Ce s-a făcut”; also above the rows when there is no checklist.
        public var header: String
        /// Under it, with a checklist: „Atinge ce s-a făcut. Prețul și marca sunt opționale.”
        public var checklistHint: String
        /// Under it, rows alone: „Câte un rând pentru fiecare lucrare. Prețul e opțional.”
        public var rowsHint: String
        /// A row's name field: „Ce s-a făcut”.
        public var rowName: String
    }

    /// A note, in the kind's words.
    public struct Note: Hashable, Sendable {
        /// The field's title: „Pentru ce”.
        public var label: String
        /// Its example: „Un control, o durere, o trimitere…”.
        public var prompt: String
    }

    /// Who did it, in the kind's words.
    public struct Provider: Hashable, Sendable {
        /// Above the list: „Service-ul”.
        public var header: String
        /// The name field's example: „Service Exemplu SRL”.
        public var prompt: String
        /// Above the stars: „Cum a lucrat?”.
        public var rating: String
        /// What a firm or person added from the visit does.
        public var trade: ProviderTrade
    }

    /// What must be filled before the form saves: any one of `fields`, said under the button
    /// while none is.
    public struct Requirement: Hashable, Sendable {
        public var fields: Set<Field>
        /// Said when the form shows a checklist: „Bifează ce s-a făcut sau scrie totalul…”.
        public var withChecklist: String
        /// Said otherwise: „Scrie ce s-a făcut sau totalul…”.
        public var otherwise: String
    }

    /// What the visit is in the history.
    public var historyKind: HistoryKind
    /// The section page's „Adaugă…” item, „Scriu eu”'s card and the form's title: „Am fost la service”.
    public var title: String
    /// Under „Scriu eu”'s card: what the form asks, in a few words.
    public var startHint: String
    /// The symbol beside the title, in the menu and the card.
    public var symbol: String
    /// The record's title in Istoric when nothing done is listed: „Vizită la medic”.
    public var entryTitle: String
    /// The paper it asks for; nil when it asks none.
    public var paper: Paper?
    /// What was done: ticked on the category's parts and jobs (when it has any) and written in
    /// rows of one's own for the rest; nil when it isn't asked (a note says it instead).
    public var work: WorkWords?
    /// Whether a ticked part asks its brand or code: only a vehicle's parts have one.
    public var asksBrand: Bool
    /// The note it asks; nil when it asks none.
    public var note: Note?
    /// Whether it asks the section's counter (kilometres, engine hours), where the category keeps one.
    public var asksCounter: Bool
    /// The money field's title: „Total plătit”, „Cât a costat”.
    public var costLabel: String
    /// Under the money field when nothing else is said: „Dacă ai plătit ceva.”; nil for none.
    public var costHint: String?
    /// What the rows add up to is called, under the money field.
    public var sum: Sum
    /// Whether it says if the day falls within the product's warranty (`FieldRole.warrantyUntil`).
    public var checksWarranty: Bool
    /// Who did it; nil when it isn't asked.
    public var provider: Provider?
    /// What must be filled before it saves; nil saves with the day alone.
    public var requirement: Requirement?
    /// The pinned button: „Salvează vizita”.
    public var save: String
    /// The toast it closes with, beside „Anulează”: „Vizita e în istoric.”.
    public var toast: String

    /// Every field the form can show for this kind, before the category is laid over it (a
    /// counter only where the category keeps one, a checklist only where it lists parts).
    public var fields: Set<Field> {
        var fields: Set<Field> = [.cost]
        if paper != nil { fields.insert(.paper) }
        if work != nil { fields.insert(.work) }
        if note != nil { fields.insert(.note) }
        if asksCounter { fields.insert(.counter) }
        if provider != nil { fields.insert(.provider) }
        return fields
    }

    // MARK: The way back

    /// On: each kind asks what its shape says. Off: every kind, those with no visits included,
    /// gets the one form of before (the invoice, the parts with their brand, the counter, the
    /// total, who did it, saved once something is filled), with the words its category had.
    /// Kept as the way back until the owner has used the kinds; remove `everyKindBefore` with
    /// the owner's OK.
    static let formsByKind = true

    /// The one form every category had before the kinds, in the words each category had then.
    static func everyKindBefore(_ kind: VisitKind) -> VisitShape {
        var shape = service
        let words: (title: String, checklist: String, provider: String, trade: ProviderTrade, history: HistoryKind) = switch kind {
        case .service:
            (String(localized: "Am fost la service"), String(localized: "Ce s-a făcut"), String(localized: "Service-ul"), .mechanic, .maintenance)
        case .vet:
            (String(localized: "Am fost la veterinar"), String(localized: "Ce i s-a făcut"), String(localized: "Veterinarul"), .vet, .visit)
        case .job:
            (String(localized: "Am chemat un meseriaș"), String(localized: "Ce a lucrat"), String(localized: "Meseriașul"), .handyman, .repair)
        case .doctor:
            (String(localized: "Am fost la medic"), String(localized: "Ce s-a făcut"), String(localized: "Medicul"), .doctor, .visit)
        case .repair, .upkeep, .note, .none:
            (String(localized: "Am făcut o lucrare"), String(localized: "Ce s-a făcut"), String(localized: "Cine a lucrat"), .other, .repair)
        }
        shape.title = words.title
        shape.work?.header = words.checklist
        shape.provider?.header = words.provider
        shape.provider?.trade = words.trade
        shape.historyKind = words.history
        return shape
    }

    // MARK: The kinds

    /// Each kind's shape, in its own words; nil for a kind with no visits.
    static func byKind(_ kind: VisitKind) -> VisitShape? {
        switch kind {
        case .service: service
        case .job: job
        case .repair: repair
        case .upkeep: upkeep
        case .doctor: doctor
        case .vet: vet
        case .note, .none: nil
        }
    }

    /// A car's or a bike's service: the invoice, the parts with price and brand, the counter, the firm, the total.
    private static var service: VisitShape {
        VisitShape(
            historyKind: .maintenance,
            title: String(localized: "Am fost la service", comment: "Logs a visit to the service, for a car or a bike."),
            startHint: String(localized: "Ce s-a făcut, cât a costat, cine a lucrat.", comment: "Under the service visit's card in Scriu eu."),
            symbol: "wrench.and.screwdriver",
            entryTitle: String(localized: "Vizită la service", comment: "A service visit's title in Istoric when nothing done is listed."),
            paper: .invoice,
            work: WorkWords(
                header: String(localized: "Ce s-a făcut"),
                checklistHint: String(localized: "Atinge ce s-a făcut. Prețul și marca sunt opționale."),
                rowsHint: String(localized: "Câte un rând pentru fiecare lucrare. Prețul e opțional.", comment: "Visit form: rows of what was done, with no checklist."),
                rowName: String(localized: "Ce s-a făcut")
            ),
            asksBrand: true,
            note: nil,
            asksCounter: true,
            costLabel: String(localized: "Total plătit"),
            costHint: nil,
            sum: .parts,
            checksWarranty: false,
            provider: Provider(header: String(localized: "Service-ul"), prompt: String(localized: "Service Exemplu SRL"),
                               rating: String(localized: "Cum a lucrat?"), trade: .mechanic),
            requirement: Requirement(
                fields: [.work, .cost, .paper],
                withChecklist: String(localized: "Bifează ce s-a făcut sau scrie totalul ca să poți salva."),
                otherwise: String(localized: "Scrie ce s-a făcut sau totalul ca să poți salva.", comment: "Visit form: what saving needs, with no checklist.")
            ),
            save: String(localized: "Salvează vizita"),
            toast: String(localized: "Vizita e în istoric.")
        )
    }

    /// A tradesperson's job: what was done, who did it, what it cost, the invoice.
    private static var job: VisitShape {
        VisitShape(
            historyKind: .repair,
            title: String(localized: "Am chemat un meseriaș"),
            startHint: String(localized: "Ce s-a lucrat, cine a lucrat, cât a costat.", comment: "Under a tradesperson's job card in Scriu eu."),
            symbol: "hammer",
            entryTitle: String(localized: "Lucrare", comment: "A tradesperson's job's title in Istoric when nothing done is listed."),
            paper: .invoice,
            work: WorkWords(
                header: String(localized: "Ce s-a lucrat", comment: "Visit form: what a tradesperson did."),
                checklistHint: String(localized: "Atinge ce s-a lucrat. Prețul e opțional.", comment: "Job form: under the checklist."),
                rowsHint: String(localized: "Câte un rând pentru fiecare lucrare. Prețul e opțional."),
                rowName: String(localized: "Ce s-a lucrat")
            ),
            asksBrand: false,
            note: nil,
            asksCounter: false,
            costLabel: String(localized: "Cât a costat"),
            costHint: nil,
            sum: .rows,
            checksWarranty: false,
            provider: Provider(header: String(localized: "Cine a lucrat"), prompt: String(localized: "Instalator Exemplu SRL"),
                               rating: String(localized: "Cum a lucrat?"), trade: .handyman),
            requirement: Requirement(
                fields: [.work, .cost, .paper],
                withChecklist: String(localized: "Bifează ce s-a lucrat sau scrie cât a costat ca să poți salva.", comment: "Job form: what saving needs."),
                otherwise: String(localized: "Scrie ce s-a lucrat sau cât a costat ca să poți salva.", comment: "Job form: what saving needs, with no checklist.")
            ),
            save: String(localized: "Salvează lucrarea", comment: "Saves a tradesperson's job."),
            toast: String(localized: "Lucrarea e în istoric.", comment: "Toast after a tradesperson's job is saved.")
        )
    }

    /// Something bought, repaired: what was fixed, where, what it cost, whether it was under warranty.
    private static var repair: VisitShape {
        VisitShape(
            historyKind: .repair,
            title: String(localized: "Am dus la reparat", comment: "Logs a repair of something bought."),
            startHint: String(localized: "Ce s-a reparat, unde, cât a costat.", comment: "Under a repair's card in Scriu eu."),
            symbol: "wrench.adjustable",
            entryTitle: String(localized: "Reparație", comment: "A repair's title in Istoric."),
            paper: .invoice,
            work: nil,
            asksBrand: false,
            note: Note(label: String(localized: "Ce s-a reparat", comment: "Repair form: what was fixed."),
                       prompt: String(localized: "Ecranul, bateria, un buton…", comment: "Example of what was repaired.")),
            asksCounter: false,
            costLabel: String(localized: "Cât a costat"),
            costHint: String(localized: "Lasă gol dacă a fost gratuită.", comment: "Under a repair's cost."),
            sum: .rows,
            checksWarranty: true,
            provider: Provider(header: String(localized: "Cine a reparat", comment: "Repair form: who fixed it."), prompt: String(localized: "Atelier Exemplu SRL"),
                               rating: String(localized: "Cum a lucrat?"), trade: .other),
            requirement: Requirement(
                fields: [.note, .cost, .paper],
                withChecklist: String(localized: "Scrie ce s-a reparat sau cât a costat ca să poți salva.", comment: "Repair form: what saving needs."),
                otherwise: String(localized: "Scrie ce s-a reparat sau cât a costat ca să poți salva.", comment: "Repair form: what saving needs.")
            ),
            save: String(localized: "Salvează reparația", comment: "Saves a repair."),
            toast: String(localized: "Reparația e în istoric.", comment: "Toast after a repair is saved.")
        )
    }

    /// An espresso machine's upkeep: what was done and what it cost, if anything.
    private static var upkeep: VisitShape {
        VisitShape(
            historyKind: .maintenance,
            title: String(localized: "Am făcut o revizie", comment: "Logs an espresso machine's upkeep."),
            startHint: String(localized: "Ce s-a făcut și cât a costat, dacă a costat.", comment: "Under an upkeep's card in Scriu eu."),
            symbol: "checklist",
            entryTitle: String(localized: "Revizie", comment: "An upkeep's title in Istoric when nothing done is listed."),
            paper: nil,
            work: WorkWords(
                header: String(localized: "Ce s-a făcut"),
                checklistHint: String(localized: "Atinge ce s-a făcut. Prețul e opțional.", comment: "Upkeep form: under the checklist."),
                rowsHint: String(localized: "Câte un rând pentru fiecare lucrare. Prețul e opțional."),
                rowName: String(localized: "Ce s-a făcut")
            ),
            asksBrand: false,
            note: nil,
            asksCounter: false,
            costLabel: String(localized: "Cât a costat"),
            costHint: String(localized: "Dacă a costat ceva.", comment: "Under an upkeep's optional cost."),
            sum: .rows,
            checksWarranty: false,
            provider: nil,
            requirement: Requirement(
                fields: [.work],
                withChecklist: String(localized: "Bifează ce s-a făcut ca să poți salva.", comment: "Upkeep form: what saving needs."),
                otherwise: String(localized: "Scrie ce s-a făcut ca să poți salva.", comment: "Upkeep form: what saving needs, with no checklist.")
            ),
            save: String(localized: "Salvează revizia", comment: "Saves an upkeep."),
            toast: String(localized: "Revizia e în istoric.", comment: "Toast after an upkeep is saved.")
        )
    }

    /// A doctor's visit: the day, who, what for, the papers, an optional cost. Saves with the day alone.
    private static var doctor: VisitShape {
        VisitShape(
            historyKind: .visit,
            title: String(localized: "Am fost la medic"),
            startHint: String(localized: "La cine, pentru ce, rețeta sau analizele.", comment: "Under a doctor's visit card in Scriu eu."),
            symbol: "stethoscope",
            entryTitle: String(localized: "Vizită la medic", comment: "A doctor's visit's title in Istoric."),
            paper: .medical,
            work: nil,
            asksBrand: false,
            note: Note(label: String(localized: "Pentru ce", comment: "A doctor's visit: what it was for."),
                       prompt: String(localized: "Un control, o durere, o trimitere…", comment: "Example of what a doctor's visit was for.")),
            asksCounter: false,
            costLabel: String(localized: "Cât a costat"),
            costHint: String(localized: "Dacă ai plătit ceva.", comment: "Under a visit's optional cost."),
            sum: .rows,
            checksWarranty: false,
            provider: Provider(header: String(localized: "Medicul sau clinica", comment: "A doctor's visit: who."), prompt: String(localized: "Clinica Exemplu"),
                               rating: String(localized: "Cum a fost?", comment: "Rating a doctor's or a vet's visit."), trade: .doctor),
            requirement: nil,
            save: String(localized: "Salvează vizita"),
            toast: String(localized: "Vizita e în istoric.")
        )
    }

    /// A vet visit: the day, the vet, what was done (the pet's vaccines and treatments), the papers, an optional cost.
    private static var vet: VisitShape {
        VisitShape(
            historyKind: .visit,
            title: String(localized: "Am fost la veterinar"),
            startHint: String(localized: "Ce i s-a făcut, la cine, fișa sau rețeta.", comment: "Under a vet visit's card in Scriu eu."),
            symbol: "pawprint",
            entryTitle: String(localized: "Vizită la veterinar", comment: "A vet visit's title in Istoric when nothing done is listed."),
            paper: .veterinary,
            work: WorkWords(
                header: String(localized: "Ce i s-a făcut"),
                checklistHint: String(localized: "Atinge ce i s-a făcut. Prețul e opțional.", comment: "Vet visit form: under the checklist."),
                rowsHint: String(localized: "Câte un rând pentru fiecare tratament. Prețul e opțional.", comment: "Vet visit form: rows, with no checklist."),
                rowName: String(localized: "Ce i s-a făcut")
            ),
            asksBrand: false,
            note: nil,
            asksCounter: false,
            costLabel: String(localized: "Cât a costat"),
            costHint: String(localized: "Dacă ai plătit ceva."),
            sum: .rows,
            checksWarranty: false,
            provider: Provider(header: String(localized: "Veterinarul"), prompt: String(localized: "Cabinet Veterinar Exemplu"),
                               rating: String(localized: "Cum a fost?"), trade: .vet),
            requirement: nil,
            save: String(localized: "Salvează vizita"),
            toast: String(localized: "Vizita e în istoric.")
        )
    }
}

extension VisitShape.Paper {
    /// Whether it is an invoice: another photo of one is known by its number, day and total
    /// (`PaperIdentity`), and said so (`DSFiledPaperNotice`).
    public var isInvoice: Bool { self == .invoice }

    /// How the paper is kept: an invoice as one, a doctor's or a vet's paper as a report.
    public var documentKind: DocumentKind {
        switch self {
        case .invoice: .invoice
        case .medical, .veterinary: .report
        }
    }

    /// The card that asks for it.
    public var action: String {
        switch self {
        case .invoice: String(localized: "Atașează factura")
        case .medical: String(localized: "Atașează rețeta sau analizele", comment: "Visit form: asks for a doctor's paper.")
        case .veterinary: String(localized: "Atașează fișa sau rețeta", comment: "Visit form: asks for a vet's paper.")
        }
    }

    /// Under the card, when the form ticks what the paper lists.
    public var hintTicking: String {
        switch self {
        case .invoice: String(localized: "Bifez singur ce scrie pe ea și trec sumele.")
        case .medical: String(localized: "Sau biletul de trimitere. Bifez singur ce găsesc scris.", comment: "Visit form: a doctor's paper ticks what it lists.")
        case .veterinary: String(localized: "Sau carnetul de vaccinări. Bifez singur ce găsesc scris.", comment: "Visit form: a vet's paper ticks what it lists.")
        }
    }

    /// Under the card, when the form writes what it lists in rows.
    public var hintRows: String {
        switch self {
        case .invoice: String(localized: "Trec singur rândurile și sumele de pe ea.", comment: "Visit form: the invoice fills the rows.")
        case .medical: String(localized: "Sau biletul de trimitere. Trec singur ce găsesc scris.", comment: "Visit form: a doctor's paper fills the rows.")
        case .veterinary: String(localized: "Sau carnetul de vaccinări. Trec singur ce găsesc scris.", comment: "Visit form: a vet's paper fills the rows.")
        }
    }

    /// Under the card, when the form only keeps it, with its day and total.
    public var hintKeeping: String {
        switch self {
        case .invoice: String(localized: "O păstrez și trec data și suma de pe ea.", comment: "Visit form: the invoice is kept, its day and total read.")
        case .medical: String(localized: "Sau biletul de trimitere. Le păstrez cu vizita.", comment: "Visit form: a doctor's papers are kept with the visit.")
        case .veterinary: String(localized: "Sau carnetul de vaccinări. Le păstrez cu vizita.", comment: "Visit form: a vet's papers are kept with the visit.")
        }
    }

    /// The choice of where the photo comes from: its title.
    public var sourceTitle: String {
        switch self {
        case .invoice: String(localized: "Atașează factura")
        case .medical: String(localized: "Atașează o hârtie de la medic", comment: "Title of the photo source choice for a doctor's paper.")
        case .veterinary: String(localized: "Atașează o hârtie de la veterinar", comment: "Title of the photo source choice for a vet's paper.")
        }
    }

    /// The choice's camera button.
    public var camera: String {
        switch self {
        case .invoice: String(localized: "Fotografiază factura")
        case .medical, .veterinary: String(localized: "Fotografiază hârtia", comment: "Photo source: the camera, for a doctor's or a vet's paper.")
        }
    }

    /// While it is read.
    public var reading: String {
        switch self {
        case .invoice: String(localized: "Citesc factura…")
        case .medical, .veterinary: String(localized: "Citesc hârtia…", comment: "While a doctor's or a vet's paper is read.")
        }
    }

    /// Read, and its photo kept.
    public var attached: String {
        switch self {
        case .invoice: String(localized: "Factura e atașată")
        case .medical, .veterinary: String(localized: "Hârtia e atașată", comment: "A doctor's or a vet's paper is attached to the visit.")
        }
    }

    /// Read, its photo not kept (it shows a whole card number).
    public var read: String {
        switch self {
        case .invoice: String(localized: "Am citit factura")
        case .medical, .veterinary: String(localized: "Am citit hârtia", comment: "A doctor's or a vet's paper was read, its photo not kept.")
        }
    }

    /// Couldn't be read.
    public var unread: String {
        switch self {
        case .invoice: String(localized: "Factura nu s-a citit")
        case .medical, .veterinary: String(localized: "Hârtia nu s-a citit", comment: "A doctor's or a vet's paper couldn't be read.")
        }
    }

    /// Rows ticked off it.
    public func ticked(_ count: Int) -> String {
        switch self {
        case .invoice: String(localized: "Am bifat \(count) rânduri de pe factură. Verifică-le.", comment: "Visit flow: rows ticked from a scanned invoice")
        case .medical, .veterinary: String(localized: "Am bifat \(count) rânduri de pe hârtie. Verifică-le.", comment: "Visit flow: rows ticked from a doctor's or a vet's paper.")
        }
    }

    /// Rows written off it.
    public func written(_ count: Int) -> String {
        switch self {
        case .invoice: String(localized: "Am trecut \(count) rânduri de pe factură. Verifică-le.", comment: "Visit flow: rows written from a scanned invoice.")
        case .medical, .veterinary: String(localized: "Am trecut \(count) rânduri de pe hârtie. Verifică-le.", comment: "Visit flow: rows written from a doctor's or a vet's paper.")
        }
    }

    /// Nothing on it to tick.
    public var nothingTicked: String { String(localized: "Nu am găsit rânduri de bifat. Bifează de mână.") }

    /// Nothing on it to write in rows.
    public var nothingWritten: String { String(localized: "Nu am găsit rânduri pe ea. Scrie-le de mână.", comment: "Visit flow: no rows found on the paper.") }

    /// Kept, its day, total and who issued it written in.
    public var kept: String { String(localized: "Am trecut data, suma și numele de pe ea. Verifică-le.", comment: "Visit flow: the paper's day, total and issuer were filled in.") }

    /// A photo that couldn't be read, when the form ticks.
    public var failedTicking: String { String(localized: "Încearcă o poză mai clară. Poți bifa și de mână.") }

    /// A photo that couldn't be read, when the form doesn't tick.
    public var failed: String { String(localized: "Încearcă o poză mai clară. Poți scrie și de mână.", comment: "Visit flow: the paper couldn't be read; the form can be filled by hand.") }
}
