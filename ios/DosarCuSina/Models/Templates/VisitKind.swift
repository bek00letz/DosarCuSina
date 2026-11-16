import Foundation

/// What a category's visits are: a car goes to the service, a home gets a tradesperson, a
/// product goes to be repaired, a person to the doctor, a pet to the vet; a plant takes a note;
/// a subscription, a person's documents or a tenancy take none. Declared by every category, with
/// no default (`CategoryBehavior.visit`): a built-in states it in `BuiltInTemplates`, a category
/// of one's own gets it from its switch („Are revizii sau lucrări”, `CategorySwitches.visit(for:)`).
/// What the visit form asks, and in which words, is the kind's shape (`shape`, `VisitShape`), the
/// one place that says it.
///
/// Raw values are part of the `.dosar` contract (`behavior.visit`).
public enum VisitKind: String, Codable, Sendable, CaseIterable {
    /// „Am fost la service”: the invoice, the parts and jobs (with price and brand), the counter,
    /// the firm, the total. A car, a bike, a machine of one's own counted by kilometres or hours.
    case service
    /// „Am chemat un meseriaș”: what was done, who did it, what it cost, the invoice. A home, a
    /// category of one's own serviced by time (a piano, a boiler), *Altele*.
    case job
    /// „Am dus la reparat”: what was fixed, where, what it cost, whether it was under warranty.
    /// Something bought (*Garanții*).
    case repair
    /// „Am făcut o revizie”: what was done (decalcifiere, service) and what it cost, if anything.
    /// An espresso machine.
    case upkeep
    /// „Am fost la medic”: the day, the doctor or clinic, what for, the papers (rețeta, analizele,
    /// biletul), an optional cost. It saves with its day alone.
    case doctor
    /// „Am fost la veterinar”: the day, the vet, what was done (the pet's vaccines, deparazitări,
    /// tratamente), the papers, an optional cost.
    case vet
    /// No visits: Istoric takes a dated note instead („Adaugă o notă”). A plant.
    case note
    /// No visits, and nothing typed into Istoric by hand: a subscription (its bills come with a
    /// photo), a person, their documents, a tenancy.
    case none

    /// What the visit form asks for this kind; nil when the kind has no visits (`note`, `none`).
    /// The way back (`VisitShape.formsByKind` off) gives every kind the one form of before.
    public var shape: VisitShape? {
        guard VisitShape.formsByKind else { return .everyKindBefore(self) }
        return VisitShape.byKind(self)
    }

    /// Whether a visit is offered for its sections: in the section page's „Adaugă…” menu and its
    /// Istoric pocket, in „Scriu eu”, and for an invoice read by capture.
    public var offersVisit: Bool { shape != nil }

    /// Whether Istoric takes a dated note in place of a visit („Adaugă o notă”).
    public var addsNote: Bool { VisitShape.formsByKind && self == .note }

    // MARK: Stored

    /// The kind a stored `behavior.visit` says. Missing (a category from before visits had kinds,
    /// a backup from then) reads as no visits; `OwnCategoryVisitsStep` gives a category of one's own
    /// its switch's kind, and the catalog writes the built-ins' own. A kind from a newer version
    /// reads as a job done, the plain visit that hides nothing. The earlier form, an object of words
    /// (`{"title": …, "trade": "mechanic"}`), reads as the kind its trade names.
    init(stored value: JSONValue?) {
        switch value {
        case .string(let raw)?:
            self = VisitKind(rawValue: raw) ?? .job
        case .object(let words)?:
            guard case .string(let trade)? = words["trade"] else { self = .job; return }
            self = switch ProviderTrade(rawValue: trade) {
            case .mechanic?: .service
            case .vet?: .vet
            case .doctor?: .doctor
            default: .job
            }
        default:
            self = .none
        }
    }
}
