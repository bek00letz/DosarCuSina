import Foundation

/// "Adaugă o secțiune" as one category shows it, read from what the category declares: its
/// option in the catalog (`offerTitle`, its summary, its group in `SectionOffers`), what the
/// essentials step asks (its essential fields, whose a personal document is, where a section
/// that may belong to another goes) and says (the name's example, from its part or what its
/// sections are called), and what the deadlines step says under its list. Never a test of which
/// category it is. Every word the flow says is here or in `AddSectionWording`, which is what
/// `docs/COPY_MATRIX.md` lists (`CopyMatrixTests.addSectionSection`); the flow
/// (`AddSectionFlow`) is a shaped screen and holds no words of its own.
struct AddSectionForm: Equatable {
    let definition: TemplateDefinition

    init(_ definition: TemplateDefinition) {
        self.definition = definition
    }

    // MARK: The catalog

    /// A category's option in the catalog, from its name, its line and its behaviour alone
    /// (what the catalog reads of every category, without its fields and deadlines).
    struct Option: Equatable {
        /// One thing rather than the category ("Mașină", not "Mașini").
        let title: String
        /// Under it: the category's own line, when it has one.
        let summary: String?
        /// Where it is offered; nil when its sections are only added under another one.
        let group: SectionOffers.Group?

        init(name: String, summary: String?, behavior: CategoryBehavior) {
            title = behavior.offerTitle(name: name)
            self.summary = summary.flatMap { $0.isEmpty ? nil : $0 }
            group = SectionOffers.group(of: behavior)
        }
    }

    var option: Option { Option(name: definition.name, summary: definition.summary, behavior: definition.behavior) }

    // MARK: The essentials

    /// Above the fields: the category it goes in.
    var header: String { definition.name }

    /// The fields asked for when adding: only those marked essential.
    var essentialFields: [FieldDefinition] { definition.allFields.filter(\.isEssential) }

    /// How one of its sections is usually called, from the part it plays or what its sections
    /// are called; nil when it declares neither, and the footnote says no example.
    var nameExample: String? { AddSectionWording.nameExample(for: definition.behavior) }

    /// Under the name.
    var nameFootnote: String {
        nameExample.map { AddSectionWording.nameFootnote(example: $0) } ?? AddSectionWording.nameFootnoteWithoutExample
    }

    /// Whether it asks whose it is: a personal document, filed under its holder.
    var asksHolder: Bool { definition.behavior.role == .personalDocument }

    /// The part it may be filed under (a home, a car, a person), for the choice of where it goes.
    var belongsTo: CategoryBehavior.Role? { definition.behavior.mayBelongTo }

    /// Under the fields when it asks none.
    var detailsLater: String? { essentialFields.isEmpty ? AddSectionWording.detailsLater : nil }

    /// The essentials' button: on to the deadlines when there are some to offer, else it adds.
    func essentialsAction(offersDeadlines: Bool) -> String {
        offersDeadlines ? AddSectionWording.next : AddSectionWording.add
    }

    // MARK: The deadlines

    /// Under a deadline's title: when it reminds, then the category's note on it.
    static func deadlineSubtitle(_ blueprint: ObligationBlueprint, values: FieldValues) -> String {
        [ReminderWording.sentence(blueprint.reminders(for: values)), blueprint.note]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: AddSectionWording.lineBreak)
    }

    /// Under the list, when some deadline asks its first date (it starts unticked,
    /// `PlannedObligation.startsSelected`): it can be added later, and from a photo of the paper
    /// only when a photo of some document sets one of them (`CaptureKindProfile.photoSetsDeadline`).
    func laterNote(for planned: [PlannedObligation]) -> String? {
        let asked = planned.filter(\.asksFirstDate)
        guard !asked.isEmpty else { return nil }
        let fromAPhoto = asked.contains { CaptureKindProfile.photoSetsDeadline($0.blueprint.key, inCategory: definition.key) }
        return fromAPhoto ? AddSectionWording.datesLaterOrFromAPhoto : AddSectionWording.datesLater
    }
}

/// The words "Adaugă o secțiune" says the same way for every category, and the ones it says by
/// what a category declares (`nameExample(for:)`). A category's own words (its name, summary,
/// fields and deadlines) are its definition's.
enum AddSectionWording {
    /// Between the lines of a deadline's subtitle.
    static let lineBreak = "\n"

    // MARK: The catalog

    static var catalogTitle: String { String(localized: "Ce adaugi?", comment: "Title of the add-section catalog.") }
    static var shortlistHeader: String { String(localized: "Cele mai des folosite", comment: "Header of the main ready-made sections.") }
    static var othersHeader: String {
        String(localized: "Alte categorii", comment: "Header of the other ready-made categories a new section can be of.")
    }
    static var customOption: String { String(localized: "Altceva…", comment: "Creates a section of the person's own.") }
    static var customOptionHint: String {
        String(localized: "Îi dai tu un nume și alegi ce ține minte.", comment: "Explains the custom section option.")
    }

    // MARK: A category of one's own

    static var customTitle: String {
        String(localized: "Categorie nouă", comment: "Title of the step that describes a category of one's own.")
    }
    static var next: String { String(localized: "Continuă") }

    // The first version's step, not shown (`CustomSectionStep.offersPocketList`).
    static var customName: String { String(localized: "Cum se numește") }
    static var customNamePrompt: String { String(localized: "Barca, Rulota, Pianul") }
    static var customKeeps: String { String(localized: "Ce ține minte") }

    /// A pocket's one-line explanation in the first version's step.
    static func pocketExplanation(_ pocket: SectionPocket) -> String {
        switch pocket {
        case .upcoming: String(localized: "Termene, cu amintiri din timp.", comment: "Pocket explanation.")
        case .tenants: String(localized: "Contractele chiriașilor și chiria.", comment: "Pocket explanation.")
        case .products: String(localized: "Lucruri cumpărate, cu garanția lor.", comment: "Pocket explanation.")
        case .subscriptions: String(localized: "Ce plătești lunar sau anual.", comment: "Pocket explanation.")
        case .plants: String(localized: "Plantele din casă, cu udatul lor.", comment: "Pocket explanation.")
        case .documents: String(localized: "Poze și PDF-uri cu actele și facturile.", comment: "Pocket explanation.")
        case .history: String(localized: "Ce s-a făcut, când și cât a costat.", comment: "Pocket explanation.")
        case .people: String(localized: "Cine are grijă de el, cu telefonul lui.", comment: "Pocket explanation.")
        case .money: String(localized: "Cât ai cheltuit pe el.", comment: "Pocket explanation.")
        case .keyFacts: String(localized: "Coduri, numere și tot ce cauți des.", comment: "Pocket explanation.")
        }
    }

    // MARK: The essentials

    static var essentialsTitle: String { String(localized: "Ce trebuie știut", comment: "Title of the essentials step.") }
    static var name: String { String(localized: "Nume") }

    /// Under the name, with an example that fits the category: „Cum îi spui acasă, de exemplu „Golful”.”
    static func nameFootnote(example: String) -> String {
        String(localized: "Cum îi spui acasă, de exemplu „\(example)”.",
               comment: "Add form, under a new section's name: an example of a name that fits its category, such as „Golful” for a car.")
    }

    /// Under the name, for a category that declares nothing an example could come from.
    static var nameFootnoteWithoutExample: String {
        String(localized: "Cum vrei să apară în dosar.", comment: "Add form, under a new section's name, for a category with no example name.")
    }

    /// How one of a category's sections is usually called, by the part it plays (a personal
    /// document, a person, a subscription), else by what its sections are called (a car, a home,
    /// a pet…); nil for one that declares neither. A home or a car of one's own (a category whose
    /// sections keep bills plays a home) is named by what its sections are called, never by its part.
    static func nameExample(for behavior: CategoryBehavior) -> String? {
        switch behavior.role {
        case .personalDocument?:
            return String(localized: "Buletinul", comment: "Example name of a new personal document, in „Cum îi spui acasă, de exemplu …”.")
        case .holder?:
            return String(localized: "Mama", comment: "Example name of a new person documents are filed under, in „Cum îi spui acasă, de exemplu …”.")
        case .subscription?:
            return String(localized: "Internetul", comment: "Example name of a new subscription, in „Cum îi spui acasă, de exemplu …”.")
        case .home?, .vehicle?, nil:
            break
        }
        switch behavior.sectionNoun {
        case .car?:
            return String(localized: "Golful", comment: "Example name of a new car, in „Cum îi spui acasă, de exemplu …”.")
        case .home?:
            return String(localized: "Apartamentul", comment: "Example name of a new home, in „Cum îi spui acasă, de exemplu …”.")
        case .pet?:
            // PawPaw: the owner's grey tabby.
            return String(localized: "PawPaw", comment: "Example name of a new pet, in „Cum îi spui acasă, de exemplu …”.")
        case .bike?:
            return String(localized: "Bicicleta de oraș", comment: "Example name of a new bike, in „Cum îi spui acasă, de exemplu …”.")
        case .plant?:
            return String(localized: "Ficusul din sufragerie", comment: "Example name of a new plant, in „Cum îi spui acasă, de exemplu …”.")
        case .espressoMachine?:
            return String(localized: "Espressorul din bucătărie", comment: "Example name of a new espresso machine, in „Cum îi spui acasă, de exemplu …”.")
        case nil:
            return nil
        }
    }

    static var holderTitle: String { String(localized: "Al cui este") }
    static var holderFootnote: String { String(localized: "Actele stau grupate pe persoane.") }
    static var detailsLater: String {
        String(localized: "Restul detaliilor le completezi oricând din pagina secțiunii, cu Editează.", comment: "Footnote when a category has no essential fields.")
    }

    // MARK: The deadlines

    static var deadlinesTitle: String { String(localized: "Termene", comment: "Header of the obligations list.") }
    static var deadlinesIntro: String {
        String(localized: "Alege ce vrei să-ți amintim. Datele le poți schimba oricând.", comment: "Intro of the obligations step.")
    }
    static var nextDate: String { String(localized: "Următoarea dată") }
    static var datesLaterOrFromAPhoto: String {
        String(localized: "Pe cele care cer o dată le poți adăuga și mai târziu, din pagina secțiunii sau dintr-o poză a actului.",
               comment: "Under the deadlines offered when adding a section: the unticked ones can be added later.")
    }
    static var datesLater: String {
        String(localized: "Pe cele care cer o dată le poți adăuga și mai târziu, din pagina secțiunii.",
               comment: "Under the deadlines offered when adding a section, when no photo of a paper sets them: the unticked ones can be added later.")
    }
    static var add: String { String(localized: "Adaugă în dosar") }

    // MARK: When something goes wrong

    static var noCategory: String {
        String(localized: "Alege mai întâi ce vrei să adaugi.", comment: "Error when finishing the add flow without a category.")
    }
}
