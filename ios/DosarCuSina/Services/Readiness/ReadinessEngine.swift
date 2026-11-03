import Foundation
import SwiftData

/// A situation the binder should be ready for.
public enum ReadinessScenario: Hashable, Sendable {
    public enum Region: String, Hashable, Sendable {
        case europeanUnion
        case outsideEU
    }

    case tripAbroad(start: CalendarDay, end: CalendarDay, region: Region, driving: Bool, withPet: Bool)
    case sellingVehicle(assetId: UUID)
    /// A claim on one of the asset's policies: the deadline `blueprintKey` names (CASCO),
    /// or, when nil, the first of its policies the binder follows.
    case insuranceClaim(assetId: UUID, blueprintKey: String? = nil)
}

/// How one check came out. Problems sort first.
public enum ReadinessStatus: Int, Hashable, Sendable, Comparable {
    /// Something will go wrong (an expired passport for a non-EU trip).
    case problem = 0
    /// Something the binder doesn't know yet; worth adding.
    case missing = 1
    /// Fine but worth a look (an RCA that ends during the trip).
    case warning = 2
    case ok = 3

    public static func < (lhs: ReadinessStatus, rhs: ReadinessStatus) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct ReadinessItem: Hashable, Sendable, Identifiable {
    public var id: String
    public var status: ReadinessStatus
    public var title: String
    public var detail: String
    /// Where to fix it or see it.
    public var route: AppRoute?
}

/// An active obligation as the readiness checks see it.
public struct ReadinessObligation: Hashable, Sendable {
    public var id: UUID
    public var due: CalendarDay
    /// The last time it was done.
    public var lastDone: CalendarDay?
    /// Policy or contract number.
    public var reference: String?

    public init(id: UUID = UUID(), due: CalendarDay, lastDone: CalendarDay? = nil, reference: String? = nil) {
        self.id = id
        self.due = due
        self.lastDone = lastDone
        self.reference = reference
    }
}

/// What the readiness checks read about one asset.
public struct ReadinessAsset: Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var templateKey: String
    public var values: FieldValues
    /// Active obligations by blueprint key: due day and the last time it was done.
    public var obligations: [String: ReadinessObligation]
    public var historyCount: Int
    /// Kinds of current (not archived) documents filed on it.
    public var documentKinds: [DocumentKind]
    /// The facts each of its category's deadlines keeps (a policy's number and claims
    /// phone), in the category's order.
    public var facts: [ReadinessFacts]

    public init(
        id: UUID = UUID(),
        name: String,
        templateKey: String,
        values: FieldValues = FieldValues(),
        obligations: [String: ReadinessObligation] = [:],
        historyCount: Int = 0,
        documentKinds: [DocumentKind] = [],
        facts: [ReadinessFacts] = []
    ) {
        self.id = id
        self.name = name
        self.templateKey = templateKey
        self.values = values
        self.obligations = obligations
        self.historyCount = historyCount
        self.documentKinds = documentKinds
        self.facts = facts
    }
}

/// One deadline's fact roles, as the readiness checks read them.
public struct ReadinessFacts: Hashable, Sendable {
    public var blueprintKey: String
    public var facts: BlueprintFacts

    public init(blueprintKey: String, facts: BlueprintFacts) {
        self.blueprintKey = blueprintKey
        self.facts = facts
    }

    /// Every deadline of `template` that keeps facts, in the template's order.
    public static func of(_ template: TemplateDefinition) -> [ReadinessFacts] {
        template.blueprints.compactMap { blueprint in blueprint.facts.map { ReadinessFacts(blueprintKey: blueprint.key, facts: $0) } }
    }
}

/// Pure checks: given a scenario and what the binder holds, a checklist with problems first.
public enum ReadinessEngine {
    public static func check(_ scenario: ReadinessScenario, assets: [ReadinessAsset], calendar: Calendar = .current) -> [ReadinessItem] {
        let items: [ReadinessItem]
        switch scenario {
        case .tripAbroad(let start, let end, let region, let driving, let withPet):
            items = trip(start: start, end: end, region: region, driving: driving, withPet: withPet, assets: assets, calendar: calendar)
        case .sellingVehicle(let id):
            items = assets.first { $0.id == id }.map { sale(of: $0) } ?? []
        case .insuranceClaim(let id, let blueprintKey):
            items = assets.first { $0.id == id }.map { claim(on: $0, blueprintKey: blueprintKey) } ?? []
        }
        return items.sorted { $0.status != $1.status ? $0.status < $1.status : $0.title < $1.title }
    }

    // MARK: Trip

    static func documents(of type: String, in assets: [ReadinessAsset]) -> [ReadinessAsset] {
        assets.filter {
            $0.templateKey == BuiltInTemplates.Key.documents
                && $0.values["document.type"]?.textValue.flatMap({ DocumentType.options.option(for: $0)?.key }) == type
        }
    }

    static func expiry(_ asset: ReadinessAsset) -> CalendarDay? {
        asset.values["document.expiry"]?.dateValue
    }

    static func trip(start: CalendarDay, end: CalendarDay, region: ReadinessScenario.Region, driving: Bool, withPet: Bool, assets: [ReadinessAsset], calendar: Calendar) -> [ReadinessItem] {
        var items: [ReadinessItem] = []
        let passports = documents(of: DocumentType.passport, in: assets)
        let idCards = documents(of: DocumentType.idCard, in: assets)

        switch region {
        case .outsideEU:
            // Most countries outside the EU ask for 6 months of validity after you return.
            let needed = RecurrenceEngine.add(.months(6), to: end, calendar: calendar)
            if passports.isEmpty {
                items.append(ReadinessItem(id: "trip.passport", status: .missing, title: String(localized: "Pașaport"),
                                           detail: String(localized: "Nu ai un pașaport în dosar. Adaugă-l ca să verificăm valabilitatea."), route: .category(BuiltInTemplates.Key.documents)))
            }
            for passport in passports {
                guard let expiry = expiry(passport) else {
                    items.append(ReadinessItem(id: "trip.passport.\(passport.id)", status: .missing, title: passport.name,
                                               detail: String(localized: "Adaugă data de expirare."), route: .asset(passport.id)))
                    continue
                }
                let ok = expiry >= needed
                items.append(ReadinessItem(
                    id: "trip.passport.\(passport.id)", status: ok ? .ok : .problem, title: passport.name,
                    detail: ok
                        ? String(localized: "Valabil până pe \(DosarFormat.longDay(expiry)), cu 6 luni după întoarcere.")
                        : String(localized: "Expiră pe \(DosarFormat.longDay(expiry)). Multe țări cer valabilitate până pe \(DosarFormat.longDay(needed))."),
                    route: .asset(passport.id)
                ))
            }
        case .europeanUnion:
            let usable = (idCards + passports).filter { (expiry($0) ?? .init(year: 0, month: 1, day: 1)) >= end }
            if let document = usable.first {
                items.append(ReadinessItem(id: "trip.identity", status: .ok, title: document.name,
                                           detail: String(localized: "Valabil pe toată durata călătoriei."), route: .asset(document.id)))
            } else {
                let known = idCards + passports
                items.append(ReadinessItem(
                    id: "trip.identity", status: known.isEmpty ? .missing : .problem, title: String(localized: "Act de identitate"),
                    detail: known.isEmpty
                        ? String(localized: "Adaugă cartea de identitate sau pașaportul.")
                        : String(localized: "Niciun act de identitate nu e valabil până la întoarcere."),
                    route: known.first.map { .asset($0.id) } ?? .category(BuiltInTemplates.Key.documents)
                ))
            }
        }

        // European health card, as a document or as a renewal on the health profile.
        let healthCards = documents(of: DocumentType.euHealthCard, in: assets)
        let cardExpiry = healthCards.compactMap(expiry).max()
            ?? assets.compactMap { $0.obligations["health.euCard"]?.due }.max()
        if let cardExpiry {
            items.append(ReadinessItem(
                id: "trip.ehic", status: cardExpiry >= end ? .ok : .warning, title: String(localized: "Card european de sănătate"),
                detail: cardExpiry >= end ? String(localized: "Valabil pe toată durata călătoriei.") : String(localized: "Expiră înainte de întoarcere."),
                route: healthCards.first.map { .asset($0.id) }
            ))
        } else {
            items.append(ReadinessItem(id: "trip.ehic", status: .missing, title: String(localized: "Card european de sănătate"),
                                       detail: String(localized: "Util în UE. Adaugă-l dacă îl ai."), route: .category(BuiltInTemplates.Key.documents)))
        }

        if driving {
            for car in assets where car.templateKey == BuiltInTemplates.Key.vehicle {
                items.append(contentsOf: carChecks(car, start: start, end: end, region: region, assets: assets, calendar: calendar))
            }
        }
        if withPet {
            for pet in assets where pet.templateKey == BuiltInTemplates.Key.pet {
                items.append(contentsOf: petChecks(pet, start: start, end: end, calendar: calendar))
            }
        }
        return items
    }

    static func validity(_ key: String, title: String, on asset: ReadinessAsset, through day: CalendarDay, status failing: ReadinessStatus) -> ReadinessItem {
        guard let obligation = asset.obligations[key] else {
            return ReadinessItem(id: "\(key).\(asset.id)", status: .missing, title: "\(title) · \(asset.name)",
                                 detail: String(localized: "Nu e în dosar."), route: .asset(asset.id))
        }
        let ok = DueDayValidity.covers(through: day, due: obligation.due)
        return ReadinessItem(
            id: "\(key).\(asset.id)", status: ok ? .ok : failing, title: "\(title) · \(asset.name)",
            detail: ok ? String(localized: "Valabil.") : String(localized: "Expiră înainte de întoarcere."),
            route: .obligation(obligation.id)
        )
    }

    static func carChecks(_ car: ReadinessAsset, start: CalendarDay, end: CalendarDay, region: ReadinessScenario.Region, assets: [ReadinessAsset], calendar: Calendar) -> [ReadinessItem] {
        var items = [
            validity("vehicle.rca", title: String(localized: "RCA"), on: car, through: end, status: .problem),
            validity("vehicle.itp", title: String(localized: "ITP"), on: car, through: end, status: .problem),
            // The vignette is needed on Romanian roads, so it matters at the start and on the way back.
            validity("vehicle.vignette", title: String(localized: "Rovinietă"), on: car, through: end, status: .warning),
        ]
        if region == .outsideEU {
            let greenCards = documents(of: DocumentType.greenCard, in: assets)
            let valid = greenCards.contains { (expiry($0) ?? CalendarDay(year: 0, month: 1, day: 1)) >= end }
            items.append(ReadinessItem(
                id: "trip.greenCard.\(car.id)", status: valid ? .ok : .missing, title: String(localized: "Carte verde · \(car.name)"),
                detail: valid ? String(localized: "Valabilă.") : String(localized: "Pentru unele țări din afara UE. Cere-o de la asigurător."),
                route: greenCards.first.map { .asset($0.id) } ?? .asset(car.id)
            ))
        }
        return items
    }

    static func petChecks(_ pet: ReadinessAsset, start: CalendarDay, end: CalendarDay, calendar: Calendar) -> [ReadinessItem] {
        var items: [ReadinessItem] = []
        let hasPassport = pet.values["pet.passport"]?.textValue?.isEmpty == false
        items.append(ReadinessItem(
            id: "trip.petPassport.\(pet.id)", status: hasPassport ? .ok : .missing, title: String(localized: "Pașaport european · \(pet.name)"),
            detail: hasPassport ? String(localized: "Trecut în dosar.") : String(localized: "Adaugă numărul pașaportului."), route: .asset(pet.id)
        ))
        guard let rabies = pet.obligations["pet.rabies"] else {
            items.append(ReadinessItem(id: "trip.rabies.\(pet.id)", status: .missing, title: String(localized: "Vaccin antirabic · \(pet.name)"),
                                       detail: String(localized: "Nu e în dosar."), route: .asset(pet.id)))
            return items
        }
        // The rabies vaccine must be at least 21 days old at the border and still valid on return.
        let latestAllowed = start.adding(days: -21, calendar: calendar)
        let doneInTime = rabies.lastDone.map { $0 <= latestAllowed } ?? false
        let validOnReturn = DueDayValidity.covers(through: end, due: rabies.due)
        let status: ReadinessStatus = doneInTime && validOnReturn ? .ok : .problem
        let detail: String
        if !validOnReturn {
            detail = String(localized: "Expiră înainte de întoarcere. Fă-l cu cel puțin 21 de zile înainte de plecare.")
        } else if !doneInTime {
            detail = String(localized: "Trebuie făcut cu cel puțin 21 de zile înainte de plecare, adică până pe \(DosarFormat.longDay(latestAllowed)).")
        } else {
            detail = String(localized: "Valabil.")
        }
        items.append(ReadinessItem(id: "trip.rabies.\(pet.id)", status: status, title: String(localized: "Vaccin antirabic · \(pet.name)"), detail: detail, route: .obligation(rabies.id)))
        return items
    }

    // MARK: Selling a car

    static func sale(of car: ReadinessAsset) -> [ReadinessItem] {
        func fact(_ key: String, _ title: String) -> ReadinessItem {
            let present = car.values[key]?.textValue?.isEmpty == false
            return ReadinessItem(id: "sale.\(key)", status: present ? .ok : .missing, title: title,
                                 detail: present ? String(localized: "Trecut în dosar.") : String(localized: "Adaugă-l înainte de vânzare."), route: .asset(car.id))
        }
        var items = [
            fact("vehicle.vin", String(localized: "Serie de șasiu (VIN)")),
            fact("vehicle.civ", String(localized: "Carte de identitate a vehiculului (CIV)")),
            ReadinessItem(id: "sale.history", status: car.historyCount > 0 ? .ok : .warning, title: String(localized: "Istoric de service"),
                          detail: car.historyCount > 0 ? String(localized: "\(car.historyCount) intrări de arătat cumpărătorului.") : String(localized: "Un istoric complet crește încrederea și prețul."),
                          route: .asset(car.id)),
            ReadinessItem(id: "sale.invoices", status: car.documentKinds.contains(.invoice) ? .ok : .warning, title: String(localized: "Facturi de service"),
                          detail: car.documentKinds.contains(.invoice) ? String(localized: "Sunt facturi în dosar.") : String(localized: "Scanează facturile pe care le ai."),
                          route: .asset(car.id)),
        ]
        if let itp = car.obligations["vehicle.itp"] {
            items.append(ReadinessItem(id: "sale.itp", status: .ok, title: String(localized: "ITP"), detail: String(localized: "Verifică să fie valabil la predare."), route: .obligation(itp.id)))
        }
        return items
    }

    // MARK: Insurance claim

    /// The policy a claim is about: the one asked for, else the first the binder follows
    /// (an active deadline), else the category's first policy.
    static func claimPolicy(on asset: ReadinessAsset, blueprintKey: String?) -> ReadinessFacts? {
        if let blueprintKey { return asset.facts.first { $0.blueprintKey == blueprintKey } }
        return asset.facts.first { asset.obligations[$0.blueprintKey] != nil } ?? asset.facts.first
    }

    static func claim(on asset: ReadinessAsset, blueprintKey: String? = nil) -> [ReadinessItem] {
        // Each policy keeps its own facts: a CASCO claim never shows the RCA's number.
        let policy = claimPolicy(on: asset, blueprintKey: blueprintKey)
        func fact(_ role: BlueprintFactRole) -> String? {
            policy?.facts.field(for: role).flatMap { asset.values[$0]?.textValue }
        }
        let policyNumber = fact(.policyNumber) ?? policy.flatMap { asset.obligations[$0.blueprintKey]?.reference }
        let claimsPhone = fact(.claimsPhone)
        return [
            ReadinessItem(id: "claim.policyNumber", status: policyNumber == nil ? .missing : .ok, title: String(localized: "Număr poliță"),
                          detail: policyNumber ?? String(localized: "Adaugă-l: îl cere asigurătorul la primul telefon."), route: .asset(asset.id)),
            ReadinessItem(id: "claim.phone", status: claimsPhone == nil ? .missing : .ok, title: String(localized: "Telefon pentru daune"),
                          detail: claimsPhone ?? String(localized: "E pe poliță sau pe site-ul asigurătorului."), route: .asset(asset.id)),
            ReadinessItem(id: "claim.policyDocument", status: asset.documentKinds.contains(.policy) ? .ok : .missing, title: String(localized: "Polița"),
                          detail: asset.documentKinds.contains(.policy) ? String(localized: "E în dosar.") : String(localized: "Scanează polița curentă."),
                          route: .asset(asset.id)),
        ]
    }
}

extension ReadinessAsset {
    /// Readiness view of every asset in the binder.
    @MainActor
    public static func fetchAll(in context: ModelContext, calendar: Calendar = .current) throws -> [ReadinessAsset] {
        let templates = try TemplateStore(context: context).templatesByKey()
        return try context.fetch(FetchDescriptor<Asset>()).map { asset in
            var obligations: [String: ReadinessObligation] = [:]
            for obligation in asset.activeObligations {
                guard let key = obligation.blueprintKey else { continue }
                let lastDone = obligation.history.first.map { CalendarDay($0.occurredAt, calendar: calendar) }
                obligations[key] = ReadinessObligation(id: obligation.id, due: obligation.dueDay(in: calendar), lastDone: lastDone, reference: obligation.reference)
            }
            return ReadinessAsset(
                id: asset.id, name: asset.name, templateKey: asset.templateKey, values: asset.values, obligations: obligations,
                historyCount: (asset.history ?? []).count,
                documentKinds: (asset.attachments ?? []).filter { !$0.isArchived }.map(\.kind),
                facts: templates[asset.templateKey].map { ReadinessFacts.of($0.definition) } ?? []
            )
        }
    }
}
