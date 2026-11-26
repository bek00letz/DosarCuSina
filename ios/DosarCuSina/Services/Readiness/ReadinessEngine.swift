import Foundation
import SwiftData

/// Pure checks: given a situation and what the binder holds, a checklist with problems
/// first. Every rule of the readiness screens lives here (which document a trip needs,
/// which policy a claim goes to, what a buyer asks for, and which sentence each check says,
/// `ReadinessWords`); the screens only draw it.
public enum ReadinessEngine {
    /// The checklist for `scenario`. `today` matters for a sale and a claim (is the ITP
    /// still valid now?); a trip is checked for its own days, and says a day already passed as
    /// passed („A expirat pe…”).
    public static func checklist(
        _ scenario: ReadinessScenario,
        assets: [ReadinessAsset],
        today: CalendarDay = CalendarDay(Date()),
        calendar: Calendar = .dosar
    ) -> ReadinessChecklist {
        switch scenario {
        case .trip(let plan):
            return ReadinessChecklist(groups: trip(plan, assets: assets, today: today, calendar: calendar))
        case .sellingVehicle(let id):
            guard let car = assets.first(where: { $0.id == id }) else { return ReadinessChecklist(groups: []) }
            return ReadinessChecklist(groups: sale(of: car, today: today))
        case .insuranceClaim(let id, let blueprintKey):
            guard let asset = assets.first(where: { $0.id == id }) else { return ReadinessChecklist(groups: []) }
            return claim(on: asset, blueprintKey: blueprintKey, today: today, people: Policyholders.people(in: assets))
        }
    }

    /// Every check of `scenario` in one list, problems first.
    public static func check(
        _ scenario: ReadinessScenario,
        assets: [ReadinessAsset],
        today: CalendarDay = CalendarDay(Date()),
        calendar: Calendar = .dosar
    ) -> [ReadinessItem] {
        checklist(scenario, assets: assets, today: today, calendar: calendar).items
    }

    /// Whether the checklist for `route` reads anything from a category that asks for
    /// Face ID. While such a category is closed the screen names nothing.
    public static func readsSensitive(_ route: ReadinessRoute, assets: [ReadinessAsset]) -> Bool {
        switch route {
        case .trip:
            return assets.contains { $0.isSensitive && readByTrip($0, in: assets) }
        case .sale(let id), .claim(let id):
            return assets.contains { $0.id == id && $0.isSensitive }
        }
    }

    // MARK: Shared readings

    static func isVehicle(_ asset: ReadinessAsset) -> Bool { asset.templateKey == BuiltInTemplates.Key.vehicle }
    static func isPet(_ asset: ReadinessAsset) -> Bool { asset.templateKey == BuiltInTemplates.Key.pet }

    /// The personal documents of one type (`DocumentType`), read by their type field: only
    /// those still current (`ReadinessAsset.isCurrentDocument`), never one replaced by a new
    /// one, whatever its printed date says. Every check that picks a document picks it here.
    static func documents(of type: String, in assets: [ReadinessAsset]) -> [ReadinessAsset] {
        assets.filter {
            $0.isCurrentDocument
                && $0.values[DocumentType.typeFieldKey]?.textValue.flatMap({ DocumentType.options.option(for: $0)?.key }) == type
        }
    }

    /// Whether a green card is this car's: it names the car's plate, or one of the two has
    /// no plate written down. Plates are compared by their letters and digits, so
    /// "B-123-ABC" is "B 123 ABC".
    static func covers(_ greenCard: ReadinessAsset, car: ReadinessAsset) -> Bool {
        func plate(_ text: String?) -> String? {
            let compact = text.map(RomanianText.compact) ?? ""
            return compact.isEmpty ? nil : compact
        }
        guard let named = plate(greenCard.values[DocumentFields.vehiclePlate]?.textValue),
              let own = plate(car.values[VehicleFields.plate]?.textValue) else { return true }
        return named == own
    }

    static func expiry(_ asset: ReadinessAsset) -> CalendarDay? {
        asset.values[DocumentFields.expiry]?.dateValue
    }

    static func hasValue(_ key: String, on asset: ReadinessAsset) -> Bool {
        asset.values[key]?.textValue.map { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? false
    }

    /// The last day a document expiring on `expiry` is good for travel: its type's travel
    /// margin before it (a passport: six months), by the one urgency rule; the expiry itself
    /// for a type without one.
    static func goodForTravelUntil(_ document: ReadinessAsset, expiry: CalendarDay, calendar: Calendar) -> CalendarDay {
        let rule = UrgencyRule(graceDays: 0, firstLeadDays: 0, maxWindowDays: 0, travelMarginDays: DocumentType.travelMarginDays(in: document.values))
        return rule.travelCutoff(before: expiry, calendar: calendar) ?? expiry
    }

    /// A deadline the section doesn't have: add it.
    static func notInBinder(_ id: String, title: ReadinessWords, detail: ReadinessWords, asset: ReadinessAsset, blueprintKey: String) -> ReadinessItem {
        ReadinessItem(id: id, status: .missing, title: title, detail: detail, action: .addDeadline(assetID: asset.id, blueprintKey: blueprintKey))
    }

    static func reminder(_ id: String, _ title: ReadinessWords, _ detail: ReadinessWords) -> ReadinessItem {
        ReadinessItem(id: id, status: .reminder, title: title, detail: detail)
    }
}

// MARK: - Trip

extension ReadinessEngine {
    /// Who and what can go: the household's members (and documents filed under no one),
    /// its cars and its pets.
    public static func tripCandidates(in assets: [ReadinessAsset]) -> TripCandidates {
        let holders = assets.filter { $0.role == .holder }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        var travellers = holders.map { TripCandidates.Traveller(traveller: .member($0.id), words: .text($0.name)) }
        // Documents filed under no one travel only while one of them is still current.
        if unfiledDocuments(in: assets).contains(where: \.isCurrentDocument) {
            travellers.append(TripCandidates.Traveller(traveller: .unfiled, words: .unfiledTraveller))
        }
        func options(_ list: [ReadinessAsset]) -> [TripCandidates.Option] {
            list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }.map { TripCandidates.Option(id: $0.id, name: $0.name) }
        }
        return TripCandidates(travellers: travellers, vehicles: options(assets.filter(isVehicle)), pets: options(assets.filter(isPet)))
    }

    /// A plan for the days given, with who goes chosen the usual way: the member it was
    /// opened from, or everyone; no car and no pet until the person says so.
    public static func defaultTrip(start: CalendarDay, end: CalendarDay, holderID: UUID?, assets: [ReadinessAsset]) -> TripPlan {
        let everyone = Set(tripCandidates(in: assets).travellers.map(\.traveller))
        let travellers: Set<TripTraveller> = holderID.map { everyone.contains(.member($0)) ? [.member($0)] : everyone } ?? everyone
        return TripPlan(start: start, end: end, region: .europeanUnion, travellers: travellers)
    }

    static func unfiledDocuments(in assets: [ReadinessAsset]) -> [ReadinessAsset] {
        let holders = Set(assets.filter { $0.role == .holder }.map(\.id))
        return assets.filter { $0.role == .personalDocument && !($0.parentId.map(holders.contains) ?? false) }
    }

    /// Every personal document filed for the traveller, those replaced by a new one included:
    /// what a document says of its holder (their citizenship) outlives it. A check picks
    /// among them with `documents(of:in:)`, which keeps only the current ones.
    static func personalDocuments(of traveller: TripTraveller, in assets: [ReadinessAsset]) -> [ReadinessAsset] {
        switch traveller {
        case .member(let id): assets.filter { $0.role == .personalDocument && $0.parentId == id }
        case .unfiled: unfiledDocuments(in: assets)
        }
    }

    /// Whether a trip reads this asset: people, their documents and health, cars, pets.
    static func readByTrip(_ asset: ReadinessAsset, in assets: [ReadinessAsset]) -> Bool {
        asset.role == .holder || asset.role == .personalDocument || isVehicle(asset) || isPet(asset)
            || asset.obligations[BuiltInBlueprints.healthEUCard] != nil
    }

    static func trip(_ plan: TripPlan, assets: [ReadinessAsset], today: CalendarDay, calendar: Calendar) -> [ReadinessGroup] {
        let candidates = tripCandidates(in: assets)
        var groups: [ReadinessGroup] = []
        for candidate in candidates.travellers where plan.travellers.contains(candidate.traveller) {
            groups.append(ReadinessGroup(
                id: "trip.person.\(candidate.traveller.key)", title: candidate.words, symbol: "person.crop.circle",
                items: travellerChecks(candidate.traveller, plan: plan, assets: assets, holderCount: candidates.travellers.count,
                                       today: today, calendar: calendar)
            ))
        }
        for car in assets.filter(isVehicle) where plan.vehicles.contains(car.id) {
            groups.append(ReadinessGroup(id: "trip.vehicle.\(car.id)", title: .text(car.name), symbol: "car.fill",
                                         items: carChecks(car, plan: plan, assets: assets, today: today, calendar: calendar)))
        }
        for pet in assets.filter(isPet) where plan.pets.contains(pet.id) {
            groups.append(ReadinessGroup(id: "trip.pet.\(pet.id)", title: .text(pet.name), symbol: "pawprint.fill",
                                         items: petChecks(pet, plan: plan, today: today, calendar: calendar)))
        }
        return groups
    }

    /// Where a missing personal document is added: under the member, photo first.
    static func addDocument(for traveller: TripTraveller) -> ReadinessAction? {
        if case .member(let id) = traveller { return .addPersonalDocument(holderID: id) }
        return nil
    }

    /// A traveller's citizenships: every one kept on the member, else every one their
    /// documents print (`Citizenship.of`); for documents filed under no one, what they print.
    /// Empty when none is known.
    static func citizenships(of traveller: TripTraveller, in assets: [ReadinessAsset]) -> [String] {
        let documents = personalDocuments(of: traveller, in: assets).map(\.values)
        switch traveller {
        case .member(let id): return Citizenship.of(person: assets.first { $0.id == id }?.values, documents: documents)
        case .unfiled: return Citizenship.read(fromDocuments: documents)
        }
    }

    /// The documents that can stand for `citizenship`: those that print it, and those that
    /// print none (most identity cards are kept without their nationality). A Moldovan passport
    /// is never a Romanian citizen's travel document.
    static func documents(_ own: [ReadinessAsset], standingFor citizenship: String) -> [ReadinessAsset] {
        own.filter { Citizenship.printed(on: $0.values).map { $0 == citizenship } ?? true }
    }

    /// What one traveller needs, by their citizenship and the region (`TravelRules`): the
    /// citizenship asked first when none is known, each document the rules ask for, the
    /// health card in the EU, the visa rules outside it.
    ///
    /// A person with several citizenships travels on the most favourable for this trip: each
    /// one's rules are checked with that citizenship's documents, and the one that leaves the
    /// least to fix wins, then the one that asks for less, then a free-movement citizenship. A
    /// Romanian and Moldovan citizen goes into the EU on the Romanian identity card or passport,
    /// and is never asked for a residence permit.
    static func travellerChecks(_ traveller: TripTraveller, plan: TripPlan, assets: [ReadinessAsset], holderCount: Int,
                                today: CalendarDay, calendar: Calendar) -> [ReadinessItem] {
        let own = personalDocuments(of: traveller, in: assets)
        let key = traveller.key
        var items: [ReadinessItem] = []
        let known = citizenships(of: traveller, in: assets)
        if known.isEmpty {
            items.append(citizenshipQuestion(for: traveller))
            items += TravelRules.requirements(forCitizenship: nil, in: plan.region).map {
                check($0, own: own, key: key, traveller: traveller, plan: plan, today: today, calendar: calendar)
            }
        } else {
            let ways = known.enumerated().map { index, citizenship in
                let checks = TravelRules.requirements(forCitizenship: citizenship, in: plan.region).map {
                    check($0, own: documents(own, standingFor: citizenship), key: key, traveller: traveller, plan: plan, today: today, calendar: calendar)
                }
                let left = checks.filter { $0.status != .ok }.count
                let freeFirst = Citizenship.group(of: citizenship) == .freeMovement ? 0 : 1
                return (checks: checks, rank: [left, checks.count, freeFirst, index])
            }
            items += ways.min { $0.rank.lexicographicallyPrecedes($1.rank) }?.checks ?? []
        }
        if TravelRules.checksHealthCard(in: plan.region) {
            items.append(healthCard(own, traveller: traveller, assets: assets, holderCount: holderCount, end: plan.end, today: today))
        }
        if TravelRules.remindsOfVisa(in: plan.region) {
            items.append(reminder("trip.visa.\(key)", .visaTitle, .visaDetail))
        }
        return items
    }

    /// The citizenship isn't known: a member is asked it (kept on them, so only once); for
    /// documents filed under no one there is no one to keep it on yet.
    static func citizenshipQuestion(for traveller: TripTraveller) -> ReadinessItem {
        let id = "trip.citizenship.\(traveller.key)"
        switch traveller {
        case .member(let member):
            return ReadinessItem(id: id, status: .missing, title: .citizenshipTitle, detail: .citizenshipAsked,
                                 action: .chooseCitizenship(holderID: member))
        case .unfiled:
            return ReadinessItem(id: id, status: .missing, title: .citizenshipTitle, detail: .citizenshipOfUnfiled)
        }
    }

    /// One document of a requirement, as the check weighs it.
    struct DatedDocument {
        var document: ReadinessAsset
        var type: String
        /// Its type's place in the requirement's order: the lower, the more preferred.
        var order: Int
        var expiry: CalendarDay
        /// Until when it counts: its expiry, a passport's travel cut-off, or the last day its
        /// kind is good for travel (`TravelRules.travelEnd`), whichever comes first.
        var countsUntil: CalendarDay
    }

    /// One requirement, met by any of its document types: the first type (in the rule's
    /// order) that covers the whole trip, and the months after it the destination asks; else
    /// the one that lasts longest, which ends too early; else a document that is no travel
    /// document (the simple identity card); else one with no expiry written down; else nothing
    /// in the binder, to add. A passport counts until its travel cut-off where the rule says so
    /// (outside the EU), the same cut-off its reminders and urgency use; every other document
    /// until it expires or its kind stops being good for travel.
    static func check(_ requirement: TravelRequirement, own: [ReadinessAsset], key: String, traveller: TripTraveller,
                      plan: TripPlan, today: CalendarDay, calendar: Calendar) -> ReadinessItem {
        let id = "trip.\(requirement.need.rawValue).\(key)"
        var found: [ReadinessAsset] = []
        var notForTravel: [ReadinessAsset] = []
        var dated: [DatedDocument] = []
        for (order, type) in requirement.accepted.enumerated() {
            for document in documents(of: type, in: own) {
                guard TravelRules.travels(document.values) else {
                    notForTravel.append(document)
                    continue
                }
                found.append(document)
                guard let expiry = expiry(document) else { continue }
                var countsUntil = requirement.countsTravelCutoff ? goodForTravelUntil(document, expiry: expiry, calendar: calendar) : expiry
                if let end = TravelRules.travelEnd(of: document.values) { countsUntil = min(countsUntil, end) }
                dated.append(DatedDocument(document: document, type: type, order: order, expiry: expiry, countsUntil: countsUntil))
            }
        }
        let lastDay = requirement.lastDayNeeded(returning: plan.end, calendar: calendar)
        let covering = dated.filter { DueDayValidity.covers(through: lastDay, due: $0.countsUntil) }
        // The most preferred type first, then the one that lasts longest.
        if let best = covering.min(by: { ($0.order, $1.countsUntil) < ($1.order, $0.countsUntil) }) {
            // An earlier choice is in the binder but doesn't last: say why this one is taken.
            let instead = dated.contains { $0.order < best.order }
            return ReadinessItem(id: id, status: .ok, title: .documentType(best.type),
                                 detail: TravelWording.valid(requirement, type: best.type, until: best.countsUntil, instead: instead),
                                 action: .open(.asset(best.document.id)))
        }
        // The one that lasts longest, the most preferred type on a tie.
        if let best = dated.min(by: { ($1.countsUntil, $0.order) < ($0.countsUntil, $1.order) }) {
            return ReadinessItem(id: id, status: .problem, title: .documentType(best.type),
                                 detail: TravelWording.ends(requirement, type: best.type, expiry: best.expiry, goodUntil: best.countsUntil, today: today),
                                 action: .open(.asset(best.document.id)))
        }
        if let simple = notForTravel.first, found.isEmpty {
            return ReadinessItem(id: id, status: .problem, title: .text(simple.name), detail: .notATravelDocument,
                                 action: addDocument(for: traveller) ?? .open(.asset(simple.id)))
        }
        if let undated = found.first {
            return ReadinessItem(id: id, status: .missing, title: .text(undated.name), detail: .undated, action: .editSection(assetID: undated.id))
        }
        return ReadinessItem(id: id, status: .missing, title: TravelWording.title(of: requirement), detail: TravelWording.missing(requirement),
                             action: addDocument(for: traveller))
    }

    /// The European health card, as a document or as the renewal on a health profile filed
    /// under the person (or, in a household of one, on its own).
    static func healthCard(_ own: [ReadinessAsset], traveller: TripTraveller, assets: [ReadinessAsset], holderCount: Int,
                           end: CalendarDay, today: CalendarDay) -> ReadinessItem {
        let id = "trip.ehic.\(traveller.key)"
        let title = ReadinessWords.documentType(DocumentType.euHealthCard)
        let cards = documents(of: DocumentType.euHealthCard, in: own)
        let profiles = assets.filter { asset in
            guard asset.obligations[BuiltInBlueprints.healthEUCard] != nil else { return false }
            switch traveller {
            case .member(let member): return asset.parentId == member || (asset.parentId == nil && holderCount <= 1)
            case .unfiled: return asset.parentId == nil
            }
        }
        let fromCards = cards.compactMap { card in expiry(card).map { (until: $0, action: ReadinessAction.open(.asset(card.id))) } }
        let fromProfiles = profiles.compactMap { profile in
            profile.obligations[BuiltInBlueprints.healthEUCard].map { (until: $0.due, action: ReadinessAction.open(.obligation($0.id))) }
        }
        guard let best = (fromCards + fromProfiles).max(by: { $0.until < $1.until }) else {
            return ReadinessItem(id: id, status: .missing, need: .optional, title: title, detail: .healthCardMissing, action: addDocument(for: traveller))
        }
        if DueDayValidity.covers(through: end, due: best.until) {
            return ReadinessItem(id: id, status: .ok, need: .optional, title: title, detail: .validUntil(best.until), action: best.action)
        }
        return ReadinessItem(id: id, status: .warning, need: .optional, title: title,
                             detail: best.until < today ? .healthCardExpired(best.until) : .healthCardEnds(best.until),
                             action: best.action)
    }

    /// A deadline that must still be valid when the trip ends (RCA, ITP).
    static func validThroughTrip(_ key: String, title: ReadinessWords, on car: ReadinessAsset, end: CalendarDay, today: CalendarDay,
                                 failing: (CalendarDay) -> ReadinessWords, passed: (CalendarDay) -> ReadinessWords,
                                 missing: ReadinessWords) -> ReadinessItem {
        let id = "\(key).\(car.id)"
        guard let obligation = car.obligations[key] else {
            return notInBinder(id, title: title, detail: missing, asset: car, blueprintKey: key)
        }
        let ok = DueDayValidity.covers(through: end, due: obligation.due)
        return ReadinessItem(
            id: id, status: ok ? .ok : .problem, title: title,
            detail: ok ? .validUntil(obligation.due) : (obligation.due < today ? passed(obligation.due) : failing(obligation.due)),
            action: .open(.obligation(obligation.id))
        )
    }

    static func carChecks(_ car: ReadinessAsset, plan: TripPlan, assets: [ReadinessAsset], today: CalendarDay, calendar: Calendar) -> [ReadinessItem] {
        let rca = car.obligations[BuiltInBlueprints.vehicleRCA]
        var items = [
            validThroughTrip(BuiltInBlueprints.vehicleRCA, title: .rcaTitle, on: car, end: plan.end, today: today,
                             failing: ReadinessWords.rcaEnds, passed: ReadinessWords.rcaExpired, missing: .rcaMissing),
            validThroughTrip(BuiltInBlueprints.vehicleITP, title: .itpTitle, on: car, end: plan.end, today: today,
                             failing: ReadinessWords.itpEnds, passed: ReadinessWords.itpExpired, missing: .itpMissing),
        ]

        // The green card comes with the RCA; a card filed on its own counts too, for the car
        // whose plate it names (one that names none counts for every car).
        let greenCards = documents(of: DocumentType.greenCard, in: assets)
            .filter { covers($0, car: car) }
            .compactMap { card in expiry(card).map { (card, $0) } }
        let greenID = "trip.greenCard.\(car.id)"
        if case let (card, until)? = greenCards.max(by: { $0.1 < $1.1 }), DueDayValidity.covers(through: plan.end, due: until) {
            items.append(ReadinessItem(id: greenID, status: .ok, title: .greenCardTitle, detail: .validUntilFeminine(until), action: .open(.asset(card.id))))
        } else if let rca, DueDayValidity.covers(through: plan.end, due: rca.due) {
            items.append(ReadinessItem(id: greenID, status: .ok, title: .greenCardTitle, detail: .greenCardWithRCA, action: .open(.obligation(rca.id))))
        } else if let rca {
            items.append(ReadinessItem(id: greenID, status: .problem, title: .greenCardTitle,
                                       detail: rca.due < today ? .greenCardRCAExpired : .greenCardRCAEnds, action: .open(.obligation(rca.id))))
        } else {
            items.append(notInBinder(greenID, title: .greenCardTitle, detail: .greenCardNoRCA, asset: car, blueprintKey: BuiltInBlueprints.vehicleRCA))
        }

        // The vignette is needed on Romanian roads: on the way to the border and on the way back.
        let vignetteKey = BuiltInBlueprints.vehicleVignette
        let vignetteID = "\(vignetteKey).\(car.id)"
        if let vignette = car.obligations[vignetteKey] {
            let action = ReadinessAction.open(.obligation(vignette.id))
            if DueDayValidity.covers(through: plan.end, due: vignette.due) {
                items.append(ReadinessItem(id: vignetteID, status: .ok, title: .vignetteTitle, detail: .validUntilFeminine(vignette.due), action: action))
            } else if DueDayValidity.covers(through: plan.start, due: vignette.due) {
                items.append(ReadinessItem(id: vignetteID, status: .warning, title: .vignetteTitle, detail: .vignetteEndsDuringTrip(vignette.due), action: action))
            } else {
                items.append(ReadinessItem(id: vignetteID, status: .problem, title: .vignetteTitle,
                                           detail: vignette.due < today ? .vignetteExpired(vignette.due) : .vignetteEndsBeforeTrip(vignette.due),
                                           action: action))
            }
        } else {
            items.append(notInBinder(vignetteID, title: .vignetteTitle, detail: .vignetteMissing, asset: car, blueprintKey: vignetteKey))
        }

        items.append(drivingLicence(for: car, plan: plan, assets: assets, today: today))
        return items
    }

    /// Someone going has to drive: a licence valid until the trip ends.
    static func drivingLicence(for car: ReadinessAsset, plan: TripPlan, assets: [ReadinessAsset], today: CalendarDay) -> ReadinessItem {
        let id = "trip.licence.\(car.id)"
        let title = ReadinessWords.documentType(DocumentType.drivingLicence)
        let going = plan.travellers.flatMap { personalDocuments(of: $0, in: assets) }
        let licences = documents(of: DocumentType.drivingLicence, in: going).compactMap { licence in expiry(licence).map { (licence, $0) } }
        if case let (licence, until)? = licences.max(by: { $0.1 < $1.1 }) {
            if DueDayValidity.covers(through: plan.end, due: until) {
                return ReadinessItem(id: id, status: .ok, title: title, detail: .validUntil(until), action: .open(.asset(licence.id)))
            }
            return ReadinessItem(id: id, status: .problem, title: title, detail: until < today ? .licenceExpired(until) : .licenceEnds(until),
                                 action: .open(.asset(licence.id)))
        }
        let firstMember = plan.travellers.compactMap { traveller -> UUID? in
            if case .member(let id) = traveller { return id }
            return nil
        }.sorted { $0.uuidString < $1.uuidString }.first
        return ReadinessItem(id: id, status: .missing, title: title, detail: .licenceMissing,
                             action: firstMember.map { .addPersonalDocument(holderID: $0) })
    }

    /// The days a first rabies vaccine takes before it counts for crossing a border (Regulation
    /// (EU) No 576/2013, Annex III): a booster given before the one before ran out counts at once.
    static let rabiesWaitDays = 21

    static func petChecks(_ pet: ReadinessAsset, plan: TripPlan, today: CalendarDay, calendar: Calendar) -> [ReadinessItem] {
        var items: [ReadinessItem] = []
        let hasPassport = hasValue(PetFields.passport, on: pet)
        items.append(ReadinessItem(
            id: "trip.petPassport.\(pet.id)", status: hasPassport ? .ok : .missing, title: .petPassportTitle,
            detail: hasPassport ? .petPassportKept : .petPassportMissing,
            action: hasPassport ? .open(.asset(pet.id)) : .editSection(assetID: pet.id)
        ))
        let rabiesID = "trip.rabies.\(pet.id)"
        if let rabies = pet.obligations[BuiltInBlueprints.petRabies] {
            items.append(ReadinessItem(id: rabiesID, rabies: rabies, plan: plan, today: today, calendar: calendar))
        } else {
            items.append(notInBinder(rabiesID, title: .rabiesTitle, detail: .rabiesMissing, asset: pet, blueprintKey: BuiltInBlueprints.petRabies))
        }
        if plan.region != .europeanUnion {
            items.append(reminder("trip.petTiter.\(pet.id)", .petRulesTitle, .petRulesDetail))
        }
        return items
    }
}

extension ReadinessItem {
    /// A pet's rabies vaccine for a trip. It must still be valid on the day back. A vaccine
    /// given less than 21 days before leaving counts only if it was a booster given before the
    /// one before ran out (done on or before the due day of the cycle it closed); a first one,
    /// or one after a lapse, waits its 21 days. When the binder can't tell which it was, the
    /// person is asked to look in the pet's passport.
    init(id: String, rabies: ReadinessObligation, plan: TripPlan, today: CalendarDay, calendar: Calendar) {
        let wait = ReadinessEngine.rabiesWaitDays
        let latestAllowed = plan.start.adding(days: -wait, calendar: calendar)
        let validOnReturn = DueDayValidity.covers(through: plan.end, due: rabies.due)
        let status: ReadinessStatus
        let detail: ReadinessWords
        if !validOnReturn {
            status = .problem
            detail = rabies.due < today ? .rabiesExpired(rabies.due) : .rabiesEnds(rabies.due)
        } else if let done = rabies.lastDone, done > latestAllowed {
            switch rabies.lastCycleDue.map({ done <= $0 }) {
            case true?:
                status = .ok
                detail = .rabiesBoosterOnTime(done, rabies.due)
            case false?:
                status = .problem
                detail = .rabiesAfterLapse(done, latestAllowed)
            case nil:
                status = .warning
                detail = .rabiesTooClose(done)
            }
        } else if rabies.lastDone == nil {
            status = .warning
            detail = .rabiesUndated(rabies.due)
        } else {
            status = .ok
            detail = .validUntil(rabies.due)
        }
        self.init(id: id, status: status, title: .rabiesTitle, detail: detail, action: .open(.obligation(rabies.id)))
    }
}

// MARK: - Selling a car

extension ReadinessEngine {
    static func sale(of car: ReadinessAsset, today: CalendarDay) -> [ReadinessGroup] {
        func fact(_ key: String, _ title: ReadinessWords, present: ReadinessWords) -> ReadinessItem {
            let has = hasValue(key, on: car)
            return ReadinessItem(id: "sale.\(key)", status: has ? .ok : .missing, title: title, detail: has ? present : .factMissing,
                                 action: has ? .open(.asset(car.id)) : .editSection(assetID: car.id))
        }

        var buyer: [ReadinessItem] = [
            reminder("sale.registration", .registrationTitle, .registrationDetail),
            fact(VehicleFields.civ, .civTitle, present: .civKept),
            fact(VehicleFields.vin, .vinTitle, present: .vinKept),
        ]

        let itpKey = BuiltInBlueprints.vehicleITP
        if let itp = car.obligations[itpKey] {
            let valid = DueDayValidity.isValid(due: itp.due, on: today)
            buyer.append(ReadinessItem(id: "sale.itp", status: valid ? .ok : .problem, title: .itpTitle,
                                       detail: valid ? .saleITPValid(itp.due) : .saleITPExpired(itp.due), action: .open(.obligation(itp.id))))
        } else {
            buyer.append(notInBinder("sale.itp", title: .itpTitle, detail: .saleITPMissing, asset: car, blueprintKey: itpKey))
        }

        let rcaKey = BuiltInBlueprints.vehicleRCA
        if let rca = car.obligations[rcaKey] {
            let valid = DueDayValidity.isValid(due: rca.due, on: today)
            buyer.append(ReadinessItem(id: "sale.rca", status: valid ? .ok : .warning, title: .rcaTitle,
                                       detail: valid ? .saleRCAValid(rca.due) : .saleRCAExpired(rca.due), action: .open(.obligation(rca.id))))
        } else {
            buyer.append(notInBinder("sale.rca", title: .rcaTitle, detail: .saleRCAMissing, asset: car, blueprintKey: rcaKey))
        }

        // What shows how the car was looked after helps the sale; the buyer can't ask for it.
        buyer.append(ReadinessItem(
            id: "sale.history", status: car.historyCount > 0 ? .ok : .missing, need: .optional, title: .serviceHistoryTitle,
            detail: car.historyCount > 0 ? .serviceHistoryCount(car.historyCount) : .serviceHistoryMissing,
            action: .open(.asset(car.id))
        ))
        let hasInvoices = car.documentKinds.contains(.invoice)
        buyer.append(ReadinessItem(
            id: "sale.invoices", status: hasInvoices ? .ok : .missing, need: .optional, title: .serviceInvoicesTitle,
            detail: hasInvoices ? .serviceInvoicesKept : .serviceInvoicesMissing,
            action: hasInvoices ? .open(.asset(car.id)) : .addDocument(assetID: car.id)
        ))
        buyer.append(reminder("sale.contract", .saleContractTitle, .saleContractDetail))
        buyer.append(reminder("sale.ownerID", .ownerIDTitle, .ownerIDDetail))

        // After the sale: what to stop or move to the buyer.
        var after: [ReadinessItem] = [reminder("sale.after.localTax", .deregisterTitle, .deregisterDetail)]
        for policy in car.allObligations where policy.kind == .insurance {
            after.append(ReadinessItem(
                id: "sale.after.cancel.\(policy.id)", status: .reminder,
                title: policy.title.isEmpty ? .cancelUnnamedPolicy : .cancelPolicy(policy.title), detail: .cancelPolicyDetail,
                action: .open(.obligation(policy.id))
            ))
        }

        // Money: what must be paid before the tax office gives the papers for the sale.
        var money: [ReadinessItem] = []
        for owed in car.allObligations where (owed.kind == .tax || owed.kind == .payment) && owed.due <= today {
            money.append(ReadinessItem(id: "sale.owed.\(owed.id)", status: .problem, title: .text(owed.title),
                                       detail: owed.amount.map { .owedWithAmount(owed.due, $0) } ?? .owed(owed.due),
                                       action: .open(.obligation(owed.id))))
        }
        money.append(reminder("sale.money.localTax", .carTaxTitle, .carTaxDetail))
        money.append(reminder("sale.money.fines", .finesTitle, .finesDetail))
        money.append(reminder("sale.money.loan", .loanTitle, .loanDetail))

        return [
            ReadinessGroup(id: "sale.buyer", title: .saleBuyerGroup, symbol: "doc.text.fill", items: buyer),
            ReadinessGroup(id: "sale.money", title: .saleMoneyGroup, symbol: "banknote.fill", items: money),
            ReadinessGroup(id: "sale.after", title: .saleAfterGroup, symbol: "checklist", items: after),
        ]
    }
}

// MARK: - Insurance claim

extension ReadinessEngine {
    /// When a policy is the one to call, by its deadline. A policy of the person's own has none.
    static func whenToUse(_ blueprintKey: String) -> ReadinessWords? {
        switch blueprintKey {
        case BuiltInBlueprints.vehicleRCA: .whenRCA
        case BuiltInBlueprints.vehicleCASCO: .whenCASCO
        case BuiltInBlueprints.homePAD: .whenPAD
        case BuiltInBlueprints.homeInsurance: .whenHomeInsurance
        default: nil
        }
    }

    /// The policies a claim on `asset` can go to: those the binder follows or knows a fact
    /// of, or every policy of its category when it knows none. Each reads its own facts.
    /// `people` are the household's, for the class of the person a policy insures.
    static func claimPolicies(on asset: ReadinessAsset, people: [Policyholders.Person] = []) -> [ReadinessPolicy] {
        let all = asset.facts.map { entry -> ReadinessPolicy in
            func value(_ role: BlueprintFactRole) -> String? {
                entry.facts.field(for: role).flatMap { asset.values[$0]?.textValue }.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            }
            let deadline = asset.obligations[entry.blueprintKey]
            let reference = deadline?.reference.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            return ReadinessPolicy(
                blueprintKey: entry.blueprintKey, title: entry.title, whenToUseWords: whenToUse(entry.blueprintKey),
                insurer: value(.insurer), policyNumber: reference ?? value(.policyNumber), claimsPhone: value(.claimsPhone),
                deadlineID: deadline?.id, validUntil: deadline?.due,
                policyholderClass: Policyholders.bonusMalus(ofPolicyholder: value(.policyholder), among: people)
            )
        }
        let known = all.filter { $0.deadlineID != nil || $0.insurer != nil || $0.policyNumber != nil || $0.claimsPhone != nil }
        return known.isEmpty ? all : known
    }

    /// The policy a claim is about: the one asked for, else the first the binder follows,
    /// else the first it knows anything of.
    static func claimPolicy(among options: [ReadinessPolicy], blueprintKey: String?) -> ReadinessPolicy? {
        if let blueprintKey, let asked = options.first(where: { $0.blueprintKey == blueprintKey }) { return asked }
        return options.first { $0.deadlineID != nil } ?? options.first
    }

    static func claim(on asset: ReadinessAsset, blueprintKey: String?, today: CalendarDay, people: [Policyholders.Person] = []) -> ReadinessChecklist {
        let options = claimPolicies(on: asset, people: people)
        let policy = claimPolicy(among: options, blueprintKey: blueprintKey)

        var policyItems: [ReadinessItem] = []
        if let policy {
            if policy.policyNumber == nil {
                policyItems.append(ReadinessItem(id: "claim.policyNumber", status: .missing, title: .policyNumberTitle, detail: .policyNumberMissing,
                                                 action: .editSection(assetID: asset.id)))
            }
            if policy.claimsPhone == nil {
                policyItems.append(ReadinessItem(id: "claim.phone", status: .missing, title: .claimsPhoneTitle, detail: .claimsPhoneMissing,
                                                 action: .editSection(assetID: asset.id)))
            }
            if let id = policy.deadlineID, let until = policy.validUntil {
                let valid = DueDayValidity.isValid(due: until, on: today)
                policyItems.append(ReadinessItem(id: "claim.validity", status: valid ? .ok : .problem, title: .policyValidityTitle,
                                                 detail: valid ? .validUntilFeminine(until) : .policyExpired(until), action: .open(.obligation(id))))
            } else {
                policyItems.append(notInBinder("claim.validity", title: .policyValidityTitle, detail: .policyValidityUnknown,
                                               asset: asset, blueprintKey: policy.blueprintKey))
            }
        }
        let hasPolicy = asset.documentKinds.contains(.policy)
        policyItems.append(ReadinessItem(
            id: "claim.policyDocument", status: hasPolicy ? .ok : .missing, need: .optional, title: .policyDocumentTitle,
            detail: hasPolicy ? .policyFiled : .policyPhotoMissing,
            action: hasPolicy ? .open(.asset(asset.id)) : .addDocument(assetID: asset.id)
        ))

        let photos: [ReadinessItem]
        let papers: [ReadinessItem]
        if isVehicle(asset) {
            photos = [
                reminder("claim.photo.cars", .photoCarsTitle, .photoCarsDetail),
                reminder("claim.photo.damage", .photoDamageTitle, .photoDamageDetail),
                reminder("claim.photo.place", .photoPlaceTitle, .photoPlaceDetail),
                reminder("claim.photo.otherDriver", .photoOtherDriverTitle, .photoOtherDriverDetail),
                reminder("claim.photo.report", .photoReportTitle, .photoReportDetail),
            ]
            papers = [
                reminder("claim.paper.driver", .paperDriverTitle, .paperDriverDetail),
                reminder("claim.paper.car", .paperCarTitle, .paperCarDetail),
                reminder("claim.paper.report", .paperReportTitle, .paperReportDetail),
            ]
        } else {
            photos = [
                reminder("claim.photo.rooms", .photoRoomsTitle, .photoRoomsDetail),
                reminder("claim.photo.source", .photoSourceTitle, .photoSourceDetail),
                reminder("claim.photo.goods", .photoGoodsTitle, .photoGoodsDetail),
            ]
            papers = [
                reminder("claim.paper.id", .paperIDTitle, .paperIDDetail),
                reminder("claim.paper.deed", .paperDeedTitle, .paperDeedDetail),
                reminder("claim.paper.report", .paperOfficialReportTitle, .paperOfficialReportDetail),
            ]
        }

        return ReadinessChecklist(
            groups: [
                ReadinessGroup(id: "claim.policy", title: .claimPolicyGroup, symbol: "doc.text.fill", items: policyItems),
                ReadinessGroup(id: "claim.photos", title: .claimPhotosGroup, symbol: "camera.fill", items: photos),
                ReadinessGroup(id: "claim.papers", title: .claimPapersGroup, symbol: "folder.fill", items: papers),
            ],
            policy: policy,
            policyOptions: options
        )
    }
}

// MARK: - Reading the binder

extension ReadinessAsset {
    /// Readiness view of every asset in the binder.
    @MainActor
    public static func fetchAll(in context: ModelContext, calendar: Calendar = .dosar) throws -> [ReadinessAsset] {
        let templates = try TemplateStore(context: context).templatesByKey()
        return make(from: try context.fetch(FetchDescriptor<Asset>()), templates: templates, calendar: calendar)
    }

    /// Readiness view of `assets`, read with their categories.
    @MainActor
    public static func make(from assets: [Asset], templates: [String: CategoryTemplate], calendar: Calendar = .dosar) -> [ReadinessAsset] {
        assets.map { asset in
            var obligations: [String: ReadinessObligation] = [:]
            var others: [ReadinessObligation] = []
            for obligation in asset.activeObligations {
                let last = obligation.history.first
                let lastDone = last.map { CalendarDay($0.occurredAt, calendar: calendar) }
                let reading = ReadinessObligation(
                    id: obligation.id, due: obligation.dueDay, lastDone: lastDone, lastCycleDue: last?.cycleDueDay, reference: obligation.reference,
                    title: obligation.title, kind: obligation.kind, amount: obligation.estimatedCost
                )
                if let key = obligation.blueprintKey { obligations[key] = reading } else { others.append(reading) }
            }
            let template = templates[asset.templateKey]
            return ReadinessAsset(
                id: asset.id, name: asset.name, templateKey: asset.templateKey,
                role: template?.behavior.role, parentId: asset.parent?.id, isSensitive: asset.isSensitive(template: template),
                wasReplaced: asset.wasReplaced, values: asset.values, obligations: obligations, otherObligations: others,
                historyCount: (asset.history ?? []).count,
                documentKinds: (asset.attachments ?? []).filter { !$0.isArchived }.map(\.kind),
                facts: template.map { ReadinessFacts.of($0.definition) } ?? []
            )
        }
    }
}
