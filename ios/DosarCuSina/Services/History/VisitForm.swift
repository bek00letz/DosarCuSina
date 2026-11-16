import Foundation

/// The visit form as one category shows it: its kind's shape (`VisitShape`) laid over what the
/// category has, its parts and jobs (a checklist only when it lists some), its counter (only one
/// that goes up), the warranty a product keeps. Every word the form says is here or in
/// `VisitFormWording`, which is what `docs/COPY_MATRIX.md` lists (`CopyMatrixTests`).
struct VisitForm: Equatable {
    let kind: VisitKind
    let shape: VisitShape
    /// The category's parts and jobs, ticked on the checklist; empty when there is no checklist.
    let components: [ComponentDefinition]
    /// The counter it asks (km, engine hours): the category's hero field, when it only goes up.
    let counterField: FieldDefinition?
    /// The product's warranty end, when the kind checks it and the category keeps one.
    let warrantyField: FieldDefinition?

    /// The form for a category's sections; nil when its visits are none (`VisitKind.offersVisit`).
    @MainActor
    static func make(for definition: TemplateDefinition) -> VisitForm? {
        make(kind: definition.behavior.visit, definition: definition)
    }

    /// The form a kind gives a category's sections; nil when the kind has no visits.
    @MainActor
    static func make(kind: VisitKind, definition: TemplateDefinition) -> VisitForm? {
        guard let shape = kind.shape else { return nil }
        let counter = shape.asksCounter ? HouseholdMutations.heroMetricField(of: definition).flatMap { field in
            MeasurementKind.forUnit(field.unit).isCumulative ? field : nil
        } : nil
        return VisitForm(
            kind: kind,
            shape: shape,
            components: shape.work == nil ? [] : definition.components,
            counterField: counter,
            warrantyField: shape.checksWarranty ? definition.field(withRole: .warrantyUntil) : nil
        )
    }

    // MARK: What it shows

    /// Whether what was done is ticked on the category's parts and jobs. Never an empty list.
    var hasChecklist: Bool { !components.isEmpty }

    /// Whether what was done is written in rows: beside the checklist ("Altceva"), or alone.
    var hasRows: Bool { shape.work != nil }

    /// The fields this category's form shows.
    var fields: Set<VisitShape.Field> {
        var fields = shape.fields
        if counterField == nil { fields.remove(.counter) }
        return fields
    }

    // MARK: Its words

    var title: String { shape.title }

    /// Under the paper's card.
    var paperHint: String? {
        guard let paper = shape.paper else { return nil }
        if hasChecklist { return paper.hintTicking }
        return hasRows ? paper.hintRows : paper.hintKeeping
    }

    /// Above the rows: "Altceva" beside a checklist, else what was done.
    var rowsHeader: String? {
        guard let work = shape.work else { return nil }
        return hasChecklist ? VisitFormWording.otherRows : work.header
    }

    /// Under the rows' header.
    var rowsHint: String? {
        guard let work = shape.work else { return nil }
        return hasChecklist ? VisitFormWording.otherRowsHint : work.rowsHint
    }

    /// The button that adds a row.
    var addRow: String? {
        guard shape.work != nil else { return nil }
        return hasChecklist ? VisitFormWording.addOther : VisitFormWording.addRow
    }

    /// What saving needs, said under the button while it isn't there; nil when it saves as it is.
    var requirementNote: String? {
        guard let requirement = shape.requirement else { return nil }
        return hasChecklist ? requirement.withChecklist : requirement.otherwise
    }

    /// Under the money field when the rows add up and no total is typed.
    func sumNote(_ sum: String) -> String {
        switch shape.sum {
        case .parts: VisitFormWording.partsAddUp(sum)
        case .rows: VisitFormWording.rowsAddUp(sum)
        }
    }

    /// What the paper's reading did, said under its notice: how many rows it ticked or wrote.
    func readNote(found: Int) -> String? {
        guard let paper = shape.paper else { return nil }
        if hasChecklist { return found > 0 ? paper.ticked(found) : paper.nothingTicked }
        if hasRows { return found > 0 ? paper.written(found) : paper.nothingWritten }
        return paper.kept
    }

    /// A paper that couldn't be read: what to do instead.
    var failedNote: String? {
        guard let paper = shape.paper else { return nil }
        return hasChecklist ? paper.failedTicking : paper.failed
    }

    /// Whether the day falls within the product's warranty, said under the date; nil when the
    /// kind doesn't check it or the product keeps no end.
    func warrantyNote(on day: CalendarDay, values: FieldValues) -> String? {
        guard let field = warrantyField, let end = values[field.key]?.dateValue else { return nil }
        let date = DosarFormat.longDay(end)
        return day <= end ? VisitFormWording.underWarranty(until: date) : VisitFormWording.warrantyEnded(on: date)
    }

    /// The record's title in Istoric: what was done when it is one or two things, else the kind's.
    func entryTitle(for items: [String]) -> String {
        let names = items.filter { !$0.isEmpty }
        switch names.count {
        case 0: return shape.entryTitle
        case 1...2: return names.joined(separator: ", ")
        default:
            return shape.sum == .parts
                ? String(localized: "Revizie: \(names.count) lucrări", comment: "History entry title for a visit with many jobs")
                : shape.entryTitle
        }
    }
}

/// The words the visit form says the same way for every kind: its frame (the date, the details,
/// the source of a photo, removing a row) and what it says when something goes wrong. A kind's
/// own words are its shape's (`VisitShape`).
enum VisitFormWording {
    static var details: String { String(localized: "Detalii") }
    static var date: String { String(localized: "Data") }
    static var otherRows: String { String(localized: "Altceva") }
    static var otherRowsHint: String { String(localized: "Ce nu e în listă.") }
    static var addOther: String { String(localized: "Adaugă altceva") }
    static var addRow: String { String(localized: "Adaugă un rând", comment: "Visit form: adds a row of what was done.") }
    static var removeRow: String { String(localized: "Scoate rândul") }
    static var rowCost: String { String(localized: "Cât a costat") }
    static var brand: String { String(localized: "Marcă sau cod") }
    static var optional: String { String(localized: "Opțional") }
    static var name: String { String(localized: "Nume") }
    static var someoneElse: String { String(localized: "Altcineva") }
    static var photos: String { String(localized: "Alege din poze") }
    static var files: String { String(localized: "Din Fișiere") }
    static var cancel: String { String(localized: "Renunță") }
    static var notSaved: String { String(localized: "Nu s-a salvat") }
    static var photoDidNotOpen: String { String(localized: "Poza nu s-a putut deschide. Încearcă din nou.") }
    static var estimate: String { String(localized: "Cifra gri e doar o estimare. Scrie cifra de la bord, dacă o știi.") }
    static var sectionGone: String { String(localized: "Secțiunea nu mai există") }
    static var sectionGoneMessage: String { String(localized: "Poate a fost ștearsă. Închide și alege alta.") }
    static var noVisits: String { String(localized: "Aici nu se notează vizite", comment: "The visit form opened for a section whose category has none.") }
    static var noVisitsMessage: String {
        String(localized: "Pe pagina secțiunii găsești ce poți adăuga.", comment: "The visit form opened for a section whose category has none: where to go.")
    }
    static var undone: String { String(localized: "Vizita a fost anulată.") }

    static func lastDone(_ date: String) -> String { String(localized: "Ultima dată: \(date)") }
    static func rating(_ value: String) -> String { String(localized: "Notă \(value) din 5") }
    static func partsAddUp(_ sum: String) -> String { String(localized: "Piesele adună \(sum). Lasă gol dacă ăsta e totalul.") }
    static func rowsAddUp(_ sum: String) -> String {
        String(localized: "Rândurile adună \(sum). Lasă gol dacă ăsta e totalul.", comment: "Under a visit's cost: what its rows add up to.")
    }
    static func underWarranty(until date: String) -> String {
        String(localized: "Era în garanție, până pe \(date).", comment: "Repair form: the day falls within the product's warranty.")
    }
    static func warrantyEnded(on date: String) -> String {
        String(localized: "Garanția se terminase pe \(date).", comment: "Repair form: the product's warranty had ended by that day.")
    }

    // What the form showed after saving, before it closed with the toast (`VisitEnding.showsWhatChanged`, off).
    static func savedIn(_ section: String) -> String { String(localized: "Salvat în istoricul \(section)") }
    static func total(_ cost: String) -> String { String(localized: "Total: \(cost)") }
    static var whatChanged: String { String(localized: "Ce s-a schimbat") }
    static var close: String { String(localized: "Închide") }
    static var undo: String { String(localized: "Anulează vizita") }
    static func firstTime(on day: String) -> String { String(localized: "Pe \(day). Prima dată în dosar.") }
    static func before(on day: String, previous: String) -> String { String(localized: "Pe \(day). Înainte: \(previous).") }
}
