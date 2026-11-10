import Foundation
import SwiftData

/// Pure checks: given a situation and what the binder holds, a checklist with problems
/// first. Every rule of the readiness screens lives here (which document a trip needs,
/// which policy a claim goes to, what a buyer asks for); the screens only draw it.
public enum ReadinessEngine {
    /// The checklist for `scenario`. `today` matters for a sale and a claim (is the ITP
    /// still valid now?); a trip is checked for its own days.
    public static func checklist(
        _ scenario: ReadinessScenario,
        assets: [ReadinessAsset],
        today: CalendarDay = CalendarDay(Date()),
        calendar: Calendar = .dosar
    ) -> ReadinessChecklist {
        switch scenario {
        case .trip(let plan):
            return ReadinessChecklist(groups: trip(plan, assets: assets, calendar: calendar))
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

    /// The personal documents of one type (`DocumentType`), read by their type field.
    static func documents(of type: String, in assets: [ReadinessAsset]) -> [ReadinessAsset] {
        assets.filter {
            $0.role == .personalDocument
                && $0.values[DocumentType.typeFieldKey]?.textValue.flatMap({ DocumentType.options.option(for: $0)?.key }) == type
        }
    }

    /// Whether a green card is this car's: it names the car's plate, or one of the two has
    /// no plate written down. Plates are compared by their letters and digits, so
    /// "B-123-ABC" is "B 123 ABC".
    static func covers(_ greenCard: ReadinessAsset, car: ReadinessAsset) -> Bool {
        func plate(_ text: String?) -> String? {
            let compact = text.map(CaptureMapping.normalizedIdentifier) ?? ""
            return compact.isEmpty ? nil : compact
        }
        guard let named = plate(greenCard.values[DocumentFields.vehiclePlate]?.textValue),
              let own = plate(car.values[VehicleFields.plate]?.textValue) else { return true }
        return named == own
    }

    static func expiry(_ asset: ReadinessAsset) -> CalendarDay? {
        asset.values[DocumentFields.expiry]?.dateValue
    }

    static func typeTitle(_ type: String) -> String {
        DocumentType.label(for: type) ?? type
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
    static func notInBinder(_ id: String, title: String, detail: String, asset: ReadinessAsset, blueprintKey: String) -> ReadinessItem {
        ReadinessItem(id: id, status: .missing, title: title, detail: detail, action: .addDeadline(assetID: asset.id, blueprintKey: blueprintKey))
    }

    static func reminder(_ id: String, _ title: String, _ detail: String) -> ReadinessItem {
        ReadinessItem(id: id, status: .reminder, title: title, detail: detail)
    }
}

// MARK: - Trip

extension ReadinessEngine {
    /// Who and what can go: the household's members (and documents filed under no one),
    /// its cars and its pets.
    public static func tripCandidates(in assets: [ReadinessAsset]) -> TripCandidates {
        let holders = assets.filter { $0.role == .holder }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        var travellers = holders.map { TripCandidates.Traveller(traveller: .member($0.id), name: $0.name) }
        if !unfiledDocuments(in: assets).isEmpty {
            travellers.append(TripCandidates.Traveller(
                traveller: .unfiled,
                name: String(localized: "Acte fără titular", comment: "Trip: personal documents not filed under any person, chosen as one traveller.")
            ))
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

    static func trip(_ plan: TripPlan, assets: [ReadinessAsset], calendar: Calendar) -> [ReadinessGroup] {
        let candidates = tripCandidates(in: assets)
        var groups: [ReadinessGroup] = []
        for candidate in candidates.travellers where plan.travellers.contains(candidate.traveller) {
            groups.append(ReadinessGroup(
                id: "trip.person.\(candidate.traveller.key)", title: candidate.name, symbol: "person.crop.circle",
                items: travellerChecks(candidate.traveller, plan: plan, assets: assets, holderCount: candidates.travellers.count, calendar: calendar)
            ))
        }
        for car in assets.filter(isVehicle) where plan.vehicles.contains(car.id) {
            groups.append(ReadinessGroup(id: "trip.vehicle.\(car.id)", title: car.name, symbol: "car.fill",
                                         items: carChecks(car, plan: plan, assets: assets, calendar: calendar)))
        }
        for pet in assets.filter(isPet) where plan.pets.contains(pet.id) {
            groups.append(ReadinessGroup(id: "trip.pet.\(pet.id)", title: pet.name, symbol: "pawprint.fill",
                                         items: petChecks(pet, plan: plan, calendar: calendar)))
        }
        return groups
    }

    /// Where a missing personal document is added: under the member, photo first.
    static func addDocument(for traveller: TripTraveller) -> ReadinessAction? {
        if case .member(let id) = traveller { return .addPersonalDocument(holderID: id) }
        return nil
    }

    static func travellerChecks(_ traveller: TripTraveller, plan: TripPlan, assets: [ReadinessAsset], holderCount: Int, calendar: Calendar) -> [ReadinessItem] {
        let own = personalDocuments(of: traveller, in: assets)
        let key = traveller.key
        var items: [ReadinessItem] = []
        switch plan.region {
        case .europeanUnion:
            items.append(identityInsideEU(own, key: key, traveller: traveller, end: plan.end))
            items.append(healthCard(own, traveller: traveller, assets: assets, holderCount: holderCount, end: plan.end))
        case .outsideEU:
            items.append(passportOutsideEU(own, key: key, traveller: traveller, end: plan.end, calendar: calendar))
        }
        return items
    }

    /// Inside the EU a valid identity card is enough until its printed expiry; a passport
    /// does as well, also until its printed expiry (the travel cut-off is for outside the EU).
    static func identityInsideEU(_ own: [ReadinessAsset], key: String, traveller: TripTraveller, end: CalendarDay) -> ReadinessItem {
        let id = "trip.identity.\(key)"
        let cards = documents(of: DocumentType.idCard, in: own)
        let passports = documents(of: DocumentType.passport, in: own)
        func latest(_ list: [ReadinessAsset]) -> (ReadinessAsset, CalendarDay)? {
            list.compactMap { document in expiry(document).map { (document, $0) } }.max { $0.1 < $1.1 }
        }
        if case let (card, until)? = latest(cards), DueDayValidity.covers(through: end, due: until) {
            return ReadinessItem(id: id, status: .ok, title: typeTitle(DocumentType.idCard),
                                 detail: String(localized: "Valabilă până pe \(DosarFormat.longDay(until)). Ajunge pentru toată UE.", comment: "Trip check: an ID card valid for the whole trip."),
                                 action: .open(.asset(card.id)))
        }
        if case let (passport, until)? = latest(passports), DueDayValidity.covers(through: end, due: until) {
            let why = cards.isEmpty
                ? String(localized: "Valabil până pe \(DosarFormat.longDay(until)). În UE ajunge și pașaportul.", comment: "Trip check: no ID card, but the passport is valid inside the EU.")
                : String(localized: "Valabil până pe \(DosarFormat.longDay(until)). Ia-l pe el: cartea de identitate nu mai e valabilă la întoarcere.", comment: "Trip check: the ID card ends before return, the passport covers the trip.")
            return ReadinessItem(id: id, status: .ok, title: typeTitle(DocumentType.passport), detail: why, action: .open(.asset(passport.id)))
        }
        if case let (card, until)? = latest(cards) {
            return ReadinessItem(id: id, status: .problem, title: typeTitle(DocumentType.idCard),
                                 detail: String(localized: "Expiră pe \(DosarFormat.longDay(until)), înainte să te întorci. Fă-ți alta sau ia un pașaport valabil.", comment: "Trip check: the ID card expires before the end of an EU trip."),
                                 action: .open(.asset(card.id)))
        }
        if let undated = (cards + passports).first {
            return ReadinessItem(id: id, status: .missing, title: undated.name,
                                 detail: String(localized: "Nu știu până când e valabil. Adaugă data de expirare.", comment: "Trip check: an identity document without an expiry date."),
                                 action: .editSection(assetID: undated.id))
        }
        return ReadinessItem(id: id, status: .missing, title: typeTitle(DocumentType.idCard),
                             detail: String(localized: "Nu e în dosar. Adaug-o cu o poză și verific până când e valabilă.", comment: "Trip check: no ID card in the binder."),
                             action: addDocument(for: traveller))
    }

    /// Outside the EU a passport must still be good for travel when the trip ends: its
    /// type's margin before it expires, the same cut-off its reminders and urgency use.
    static func passportOutsideEU(_ own: [ReadinessAsset], key: String, traveller: TripTraveller, end: CalendarDay, calendar: Calendar) -> ReadinessItem {
        let id = "trip.passport.\(key)"
        let passports = documents(of: DocumentType.passport, in: own)
        let dated = passports.compactMap { passport in
            expiry(passport).map { (passport: passport, expiry: $0, goodUntil: goodForTravelUntil(passport, expiry: $0, calendar: calendar)) }
        }
        if let best = dated.max(by: { $0.goodUntil < $1.goodUntil }) {
            let title = typeTitle(DocumentType.passport)
            if DueDayValidity.covers(through: end, due: best.goodUntil) {
                return ReadinessItem(id: id, status: .ok, title: title,
                                     detail: String(localized: "Bun de călătorit până pe \(DosarFormat.longDay(best.goodUntil)), după ce te întorci.", comment: "Trip check: the passport is good for travel past the end of the trip."),
                                     action: .open(.asset(best.passport.id)))
            }
            return ReadinessItem(id: id, status: .problem, title: title,
                                 detail: String(localized: "Bun de călătorit doar până pe \(DosarFormat.longDay(best.goodUntil)). Expiră pe \(DosarFormat.longDay(best.expiry)), iar multe țări nu primesc un pașaport atât de aproape de expirare. Fă-ți altul înainte de plecare.", comment: "Trip check: the passport's travel cut-off falls before the end of a trip outside the EU."),
                                 action: .open(.asset(best.passport.id)))
        }
        if let undated = passports.first {
            return ReadinessItem(id: id, status: .missing, title: undated.name,
                                 detail: String(localized: "Nu știu până când e valabil. Adaugă data de expirare.", comment: "Trip check: an identity document without an expiry date."),
                                 action: .editSection(assetID: undated.id))
        }
        return ReadinessItem(id: id, status: .missing, title: typeTitle(DocumentType.passport),
                             detail: String(localized: "Nu e în dosar. În afara UE ai nevoie de pașaport. Adaugă-l cu o poză și verific până când e bun.", comment: "Trip check: no passport for a trip outside the EU."),
                             action: addDocument(for: traveller))
    }

    /// The European health card, as a document or as the renewal on a health profile filed
    /// under the person (or, in a household of one, on its own).
    static func healthCard(_ own: [ReadinessAsset], traveller: TripTraveller, assets: [ReadinessAsset], holderCount: Int, end: CalendarDay) -> ReadinessItem {
        let id = "trip.ehic.\(traveller.key)"
        let title = typeTitle(DocumentType.euHealthCard)
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
            return ReadinessItem(id: id, status: .missing, title: title,
                                 detail: String(localized: "Te ajută dacă ai nevoie de un medic în UE. Adaugă-l dacă îl ai.", comment: "Trip check: no European health card in the binder."),
                                 action: addDocument(for: traveller))
        }
        if DueDayValidity.covers(through: end, due: best.until) {
            return ReadinessItem(id: id, status: .ok, title: title,
                                 detail: String(localized: "Valabil până pe \(DosarFormat.longDay(best.until)).", comment: "Readiness: a deadline valid until a day."),
                                 action: best.action)
        }
        return ReadinessItem(id: id, status: .warning, title: title,
                             detail: String(localized: "Expiră pe \(DosarFormat.longDay(best.until)), înainte să te întorci. Cere altul de la casa de asigurări de sănătate.", comment: "Trip check: the European health card ends before the end of the trip."),
                             action: best.action)
    }

    /// A deadline that must still be valid when the trip ends (RCA, ITP).
    static func validThroughTrip(_ key: String, title: String, on car: ReadinessAsset, end: CalendarDay, failing: (String) -> String, missing: String) -> ReadinessItem {
        let id = "\(key).\(car.id)"
        guard let obligation = car.obligations[key] else {
            return notInBinder(id, title: title, detail: missing, asset: car, blueprintKey: key)
        }
        let ok = DueDayValidity.covers(through: end, due: obligation.due)
        return ReadinessItem(
            id: id, status: ok ? .ok : .problem, title: title,
            detail: ok
                ? String(localized: "Valabil până pe \(DosarFormat.longDay(obligation.due)).", comment: "Readiness: a deadline valid until a day.")
                : failing(DosarFormat.longDay(obligation.due)),
            action: .open(.obligation(obligation.id))
        )
    }

    static func carChecks(_ car: ReadinessAsset, plan: TripPlan, assets: [ReadinessAsset], calendar: Calendar) -> [ReadinessItem] {
        let rca = car.obligations[BuiltInBlueprints.vehicleRCA]
        var items = [
            validThroughTrip(BuiltInBlueprints.vehicleRCA, title: String(localized: "RCA"), on: car, end: plan.end,
                             failing: { String(localized: "Expiră pe \($0), înainte să te întorci. Reînnoiește-l înainte de plecare.", comment: "Trip check: the RCA ends during the trip.") },
                             missing: String(localized: "Nu e în dosar. Fără RCA valabil nu ai voie să ieși cu mașina.", comment: "Trip check: no RCA deadline.")),
            validThroughTrip(BuiltInBlueprints.vehicleITP, title: String(localized: "ITP"), on: car, end: plan.end,
                             failing: { String(localized: "Expiră pe \($0), înainte să te întorci. Fă-l înainte de plecare.", comment: "Trip check: the ITP ends during the trip.") },
                             missing: String(localized: "Nu e în dosar. Adaugă data ca să verific.", comment: "Trip check: no ITP deadline.")),
        ]

        // The green card comes with the RCA; a card filed on its own counts too, for the car
        // whose plate it names (one that names none counts for every car).
        let greenCards = documents(of: DocumentType.greenCard, in: assets)
            .filter { covers($0, car: car) }
            .compactMap { card in expiry(card).map { (card, $0) } }
        let greenTitle = String(localized: "Carte verde (RCA)", comment: "Trip check: the green card, which comes with the RCA.")
        let greenID = "trip.greenCard.\(car.id)"
        if case let (card, until)? = greenCards.max(by: { $0.1 < $1.1 }), DueDayValidity.covers(through: plan.end, due: until) {
            items.append(ReadinessItem(id: greenID, status: .ok, title: greenTitle,
                                       detail: String(localized: "Valabilă până pe \(DosarFormat.longDay(until)).", comment: "Readiness: something valid until a day (feminine)."),
                                       action: .open(.asset(card.id))))
        } else if let rca, DueDayValidity.covers(through: plan.end, due: rca.due) {
            items.append(ReadinessItem(id: greenID, status: .ok, title: greenTitle,
                                       detail: String(localized: "Inclusă în RCA. Ia-o cu tine, tipărită sau pe telefon.", comment: "Trip check: the green card comes with a valid RCA."),
                                       action: .open(.obligation(rca.id))))
        } else if let rca {
            items.append(ReadinessItem(id: greenID, status: .problem, title: greenTitle,
                                       detail: String(localized: "Vine cu RCA-ul, care expiră înainte să te întorci.", comment: "Trip check: no green card because the RCA ends during the trip."),
                                       action: .open(.obligation(rca.id))))
        } else {
            items.append(notInBinder(greenID, title: greenTitle,
                                     detail: String(localized: "Vine cu RCA-ul. Adaugă RCA-ul ca să verific.", comment: "Trip check: no RCA, so no green card."),
                                     asset: car, blueprintKey: BuiltInBlueprints.vehicleRCA))
        }

        // The vignette is needed on Romanian roads: on the way to the border and on the way back.
        let vignetteKey = BuiltInBlueprints.vehicleVignette
        let vignetteID = "\(vignetteKey).\(car.id)"
        let vignetteTitle = String(localized: "Rovinietă")
        if let vignette = car.obligations[vignetteKey] {
            let day = DosarFormat.longDay(vignette.due)
            if DueDayValidity.covers(through: plan.end, due: vignette.due) {
                items.append(ReadinessItem(id: vignetteID, status: .ok, title: vignetteTitle,
                                           detail: String(localized: "Valabilă până pe \(day).", comment: "Readiness: something valid until a day (feminine)."), action: .open(.obligation(vignette.id))))
            } else if DueDayValidity.covers(through: plan.start, due: vignette.due) {
                items.append(ReadinessItem(id: vignetteID, status: .warning, title: vignetteTitle,
                                           detail: String(localized: "Expiră pe \(day), cât ești plecat. Cumpără alta pentru drumul înapoi, online sau la benzinărie.", comment: "Trip check: the vignette ends during the trip."),
                                           action: .open(.obligation(vignette.id))))
            } else {
                items.append(ReadinessItem(id: vignetteID, status: .problem, title: vignetteTitle,
                                           detail: String(localized: "A expirat pe \(day). Ai nevoie de ea până la graniță. O cumperi online sau la benzinărie.", comment: "Trip check: the vignette has ended before the trip starts."),
                                           action: .open(.obligation(vignette.id))))
            }
        } else {
            items.append(notInBinder(vignetteID, title: vignetteTitle,
                                     detail: String(localized: "Nu e în dosar. Ai nevoie de ea până la graniță și la întoarcere.", comment: "Trip check: no vignette deadline."),
                                     asset: car, blueprintKey: vignetteKey))
        }

        items.append(drivingLicence(for: car, plan: plan, assets: assets))
        return items
    }

    /// Someone going has to drive: a licence valid until the trip ends.
    static func drivingLicence(for car: ReadinessAsset, plan: TripPlan, assets: [ReadinessAsset]) -> ReadinessItem {
        let id = "trip.licence.\(car.id)"
        let title = typeTitle(DocumentType.drivingLicence)
        let going = plan.travellers.flatMap { personalDocuments(of: $0, in: assets) }
        let licences = documents(of: DocumentType.drivingLicence, in: going).compactMap { licence in expiry(licence).map { (licence, $0) } }
        if case let (licence, until)? = licences.max(by: { $0.1 < $1.1 }) {
            if DueDayValidity.covers(through: plan.end, due: until) {
                return ReadinessItem(id: id, status: .ok, title: title,
                                     detail: String(localized: "Valabil până pe \(DosarFormat.longDay(until)).", comment: "Readiness: a deadline valid until a day."),
                                     action: .open(.asset(licence.id)))
            }
            return ReadinessItem(id: id, status: .problem, title: title,
                                 detail: String(localized: "Expiră pe \(DosarFormat.longDay(until)), înainte să te întorci.", comment: "Trip check: the driving licence ends during the trip."),
                                 action: .open(.asset(licence.id)))
        }
        let firstMember = plan.travellers.compactMap { traveller -> UUID? in
            if case .member(let id) = traveller { return id }
            return nil
        }.sorted { $0.uuidString < $1.uuidString }.first
        return ReadinessItem(id: id, status: .missing, title: title,
                             detail: String(localized: "Nu e în dosar pentru cine pleacă. Adaugă permisul celui care conduce.", comment: "Trip check: no driving licence among the people going."),
                             action: firstMember.map { .addPersonalDocument(holderID: $0) })
    }

    static func petChecks(_ pet: ReadinessAsset, plan: TripPlan, calendar: Calendar) -> [ReadinessItem] {
        var items: [ReadinessItem] = []
        let hasPassport = hasValue(PetFields.passport, on: pet)
        items.append(ReadinessItem(
            id: "trip.petPassport.\(pet.id)", status: hasPassport ? .ok : .missing,
            title: String(localized: "Pașaport european", comment: "Trip check: a pet's European passport."),
            detail: hasPassport
                ? String(localized: "Numărul e în dosar. Ia pașaportul cu tine.", comment: "Trip check: the pet's passport number is in the binder.")
                : String(localized: "Adaugă numărul pașaportului. Fără el animalul nu trece granița.", comment: "Trip check: no pet passport number."),
            action: hasPassport ? .open(.asset(pet.id)) : .editSection(assetID: pet.id)
        ))
        let rabiesID = "trip.rabies.\(pet.id)"
        let rabiesTitle = String(localized: "Vaccin antirabic", comment: "Trip check: a pet's rabies vaccine.")
        if let rabies = pet.obligations[BuiltInBlueprints.petRabies] {
            // A first rabies vaccine counts from 21 days after it is given; it must still be valid on return.
            let latestAllowed = plan.start.adding(days: -21, calendar: calendar)
            let validOnReturn = DueDayValidity.covers(through: plan.end, due: rabies.due)
            let status: ReadinessStatus
            let detail: String
            if !validOnReturn {
                status = .problem
                detail = String(localized: "Expiră pe \(DosarFormat.longDay(rabies.due)), înainte să te întorci. Fă-l din nou cu cel puțin 21 de zile înainte de plecare.", comment: "Trip check: the rabies vaccine ends during the trip.")
            } else if let done = rabies.lastDone, done > latestAllowed {
                status = .problem
                detail = String(localized: "Făcut pe \(DosarFormat.longDay(done)). Trebuie făcut cu cel puțin 21 de zile înainte de plecare, adică până pe \(DosarFormat.longDay(latestAllowed)). Întreabă medicul veterinar.", comment: "Trip check: the rabies vaccine was given too close to departure.")
            } else if rabies.lastDone == nil {
                status = .warning
                detail = String(localized: "Valabil până pe \(DosarFormat.longDay(rabies.due)). Verifică în pașaport că e făcut cu cel puțin 21 de zile înainte de plecare.", comment: "Trip check: the rabies vaccine is valid but its date isn't known.")
            } else {
                status = .ok
                detail = String(localized: "Valabil până pe \(DosarFormat.longDay(rabies.due)).", comment: "Readiness: a deadline valid until a day.")
            }
            items.append(ReadinessItem(id: rabiesID, status: status, title: rabiesTitle, detail: detail, action: .open(.obligation(rabies.id))))
        } else {
            items.append(notInBinder(rabiesID, title: rabiesTitle,
                                     detail: String(localized: "Nu e în dosar. Adaugă data vaccinului ca să verific.", comment: "Trip check: no rabies vaccine deadline."),
                                     asset: pet, blueprintKey: BuiltInBlueprints.petRabies))
        }
        if plan.region == .outsideEU {
            items.append(reminder("trip.petTiter.\(pet.id)",
                                  String(localized: "Ce cere țara pentru animale", comment: "Trip reminder: rules for pets outside the EU."),
                                  String(localized: "Unele țări din afara UE cer și un test de anticorpi, făcut cu luni înainte. Întreabă medicul veterinar.", comment: "Trip reminder: rabies antibody test for some countries.")))
        }
        return items
    }
}

// MARK: - Selling a car

extension ReadinessEngine {
    static func sale(of car: ReadinessAsset, today: CalendarDay) -> [ReadinessGroup] {
        func fact(_ key: String, _ title: String, present: String) -> ReadinessItem {
            let has = hasValue(key, on: car)
            return ReadinessItem(id: "sale.\(key)", status: has ? .ok : .missing, title: title,
                                 detail: has ? present : String(localized: "Adaugă-o înainte de vânzare. O găsești pe talon.", comment: "Sale check: a value to add from the registration certificate."),
                                 action: has ? .open(.asset(car.id)) : .editSection(assetID: car.id))
        }

        var buyer: [ReadinessItem] = [
            reminder("sale.registration", String(localized: "Certificatul de înmatriculare (talonul)", comment: "Sale: the registration certificate."),
                     String(localized: "Originalul îl dai cumpărătorului.", comment: "Sale: hand the original over.")),
            fact(VehicleFields.civ, String(localized: "Cartea de identitate a vehiculului (CIV)"),
                 present: String(localized: "Seria e în dosar. Originalul îl dai cumpărătorului.", comment: "Sale check: the CIV number is in the binder.")),
            fact(VehicleFields.vin, String(localized: "Serie de șasiu (VIN)"),
                 present: String(localized: "E în dosar, pentru contract.", comment: "Sale check: the VIN is in the binder.")),
        ]

        let itpKey = BuiltInBlueprints.vehicleITP
        if let itp = car.obligations[itpKey] {
            let valid = DueDayValidity.isValid(due: itp.due, on: today)
            buyer.append(ReadinessItem(
                id: "sale.itp", status: valid ? .ok : .problem, title: String(localized: "ITP"),
                detail: valid
                    ? String(localized: "Valabil până pe \(DosarFormat.longDay(itp.due)). Cumpărătorul are nevoie de el ca să înmatriculeze mașina.", comment: "Sale check: the ITP is valid.")
                    : String(localized: "A expirat pe \(DosarFormat.longDay(itp.due)). Fără ITP valabil, cumpărătorul nu poate înmatricula mașina.", comment: "Sale check: the ITP has expired."),
                action: .open(.obligation(itp.id))
            ))
        } else {
            buyer.append(notInBinder("sale.itp", title: String(localized: "ITP"),
                                     detail: String(localized: "Nu e în dosar. Cumpărătorul are nevoie de ITP valabil ca să înmatriculeze mașina.", comment: "Sale check: no ITP deadline."),
                                     asset: car, blueprintKey: itpKey))
        }

        let rcaKey = BuiltInBlueprints.vehicleRCA
        if let rca = car.obligations[rcaKey] {
            let valid = DueDayValidity.isValid(due: rca.due, on: today)
            buyer.append(ReadinessItem(
                id: "sale.rca", status: valid ? .ok : .warning, title: String(localized: "RCA"),
                detail: valid
                    ? String(localized: "Valabil până pe \(DosarFormat.longDay(rca.due)). Nu trece la cumpărător: el își face polița lui.", comment: "Sale check: the RCA is valid; the buyer needs their own.")
                    : String(localized: "A expirat pe \(DosarFormat.longDay(rca.due)). Până la vânzare nu ai voie să circuli cu mașina.", comment: "Sale check: the RCA has expired."),
                action: .open(.obligation(rca.id))
            ))
        } else {
            buyer.append(notInBinder("sale.rca", title: String(localized: "RCA"),
                                     detail: String(localized: "Nu e în dosar. Cumpărătorul poate cere să-l vadă.", comment: "Sale check: no RCA deadline."),
                                     asset: car, blueprintKey: rcaKey))
        }

        buyer.append(ReadinessItem(
            id: "sale.history", status: car.historyCount > 0 ? .ok : .warning, title: String(localized: "Istoric de service"),
            detail: car.historyCount > 0
                ? String(localized: "\(car.historyCount) intrări de arătat cumpărătorului.", comment: "Readiness: how many history entries a buyer can be shown.")
                : String(localized: "Un istoric complet crește încrederea și prețul. Adaugă reviziile pe care le știi.", comment: "Sale check: no service history."),
            action: .open(.asset(car.id))
        ))
        let hasInvoices = car.documentKinds.contains(.invoice)
        buyer.append(ReadinessItem(
            id: "sale.invoices", status: hasInvoices ? .ok : .warning, title: String(localized: "Facturi de service"),
            detail: hasInvoices ? String(localized: "Sunt facturi în dosar.") : String(localized: "Fă poze facturilor pe care le ai.", comment: "Sale check: no invoices filed on the car."),
            action: hasInvoices ? .open(.asset(car.id)) : .addDocument(assetID: car.id)
        ))
        buyer.append(reminder("sale.contract", String(localized: "Contractul de vânzare-cumpărare", comment: "Sale: the sale contract."),
                              String(localized: "Semnat de amândoi, câte un exemplar pentru tine, pentru cumpărător și pentru primărie.", comment: "Sale: copies of the sale contract.")))
        buyer.append(reminder("sale.ownerID", String(localized: "Cartea ta de identitate", comment: "Sale: the seller's ID card."),
                              String(localized: "Pentru contract și la primărie.", comment: "Sale: why the seller's ID card is needed.")))

        // After the sale: what to stop or move to the buyer.
        var after: [ReadinessItem] = [
            reminder("sale.after.localTax", String(localized: "Scoate mașina de pe numele tău la primărie", comment: "After the sale: deregister the car at the local tax office."),
                     String(localized: "La biroul de taxe locale, cu contractul. Altfel plătești impozit pe ea mai departe.", comment: "After the sale: why to deregister the car.")),
        ]
        for policy in car.allObligations where policy.kind == .insurance {
            let name = policy.title.isEmpty ? String(localized: "polița", comment: "After the sale: a policy without a name.") : policy.title
            after.append(ReadinessItem(
                id: "sale.after.cancel.\(policy.id)", status: .reminder,
                title: String(localized: "Reziliază \(name)", comment: "After the sale: cancel a policy. The name is the deadline's, e.g. RCA or CASCO."),
                detail: String(localized: "Cu contractul de vânzare, la asigurător. Primești înapoi banii pe lunile rămase.", comment: "After the sale: cancelling a policy returns the unused months."),
                action: .open(.obligation(policy.id))
            ))
        }

        // Money: what must be paid before the tax office gives the papers for the sale.
        var money: [ReadinessItem] = []
        for owed in car.allObligations where (owed.kind == .tax || owed.kind == .payment) && owed.due <= today {
            let detail = owed.amount.map {
                String(localized: "Trebuia plătit pe \(DosarFormat.longDay(owed.due)) · \($0.formatted())", comment: "Sale check: an unpaid amount and the day it was due.")
            } ?? String(localized: "Trebuia plătit pe \(DosarFormat.longDay(owed.due)).", comment: "Sale check: an unpaid deadline and the day it was due.")
            money.append(ReadinessItem(id: "sale.owed.\(owed.id)", status: .problem, title: owed.title, detail: detail, action: .open(.obligation(owed.id))))
        }
        money.append(reminder("sale.money.localTax", String(localized: "Impozitul pe mașină, plătit pe tot anul", comment: "Sale: pay the car tax for the year."),
                              String(localized: "Primăria îți dă certificatul fiscal pentru vânzare doar fără datorii.", comment: "Sale: the tax certificate needs no debts.")))
        money.append(reminder("sale.money.fines", String(localized: "Amenzile neplătite", comment: "Sale: unpaid fines."),
                              String(localized: "Tot pentru certificatul fiscal. Le vezi pe ghiseul.ro.", comment: "Sale: where to see unpaid fines.")))
        money.append(reminder("sale.money.loan", String(localized: "Leasing sau credit pe mașină", comment: "Sale: a lease or loan on the car."),
                              String(localized: "Dacă mașina e încă în leasing sau garanție la bancă, o vinzi doar după ce e achitată.", comment: "Sale: a car under a lease or pledge.")))

        return [
            ReadinessGroup(id: "sale.buyer", title: String(localized: "Ce cere cumpărătorul", comment: "Sale group: documents a buyer asks for."), symbol: "doc.text.fill", items: buyer),
            ReadinessGroup(id: "sale.money", title: String(localized: "Bani de plătit înainte", comment: "Sale group: money owed before selling."), symbol: "banknote.fill", items: money),
            ReadinessGroup(id: "sale.after", title: String(localized: "După vânzare", comment: "Sale group: what to cancel or move after the sale."), symbol: "checklist", items: after),
        ]
    }
}

// MARK: - Insurance claim

extension ReadinessEngine {
    /// When a policy is the one to call, by its deadline. A policy of the person's own has none.
    static func whenToUse(_ blueprintKey: String) -> String? {
        switch blueprintKey {
        case BuiltInBlueprints.vehicleRCA:
            String(localized: "Când ai lovit pe altcineva: îi dai lui datele poliței. Dacă te-a lovit altcineva, plătește RCA-ul lui.", comment: "Claim: when the car's RCA is the policy to use.")
        case BuiltInBlueprints.vehicleCASCO:
            String(localized: "Pentru mașina ta, oricine e de vină.", comment: "Claim: when CASCO is the policy to use.")
        case BuiltInBlueprints.homePAD:
            String(localized: "Cutremur, inundație sau alunecare de teren.", comment: "Claim: what the mandatory home policy (PAD) covers.")
        case BuiltInBlueprints.homeInsurance:
            String(localized: "Apă de la vecini, incendiu, furt și ce mai scrie pe poliță.", comment: "Claim: what the optional home policy covers.")
        default:
            nil
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
                blueprintKey: entry.blueprintKey, title: entry.title, whenToUse: whenToUse(entry.blueprintKey),
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
        let isCar = isVehicle(asset)

        var policyItems: [ReadinessItem] = []
        if let policy {
            if policy.policyNumber == nil {
                policyItems.append(ReadinessItem(id: "claim.policyNumber", status: .missing, title: String(localized: "Număr poliță"),
                                                 detail: String(localized: "Îl cere asigurătorul la primul telefon. E scris pe poliță.", comment: "Claim check: no policy number."),
                                                 action: .editSection(assetID: asset.id)))
            }
            if policy.claimsPhone == nil {
                policyItems.append(ReadinessItem(id: "claim.phone", status: .missing, title: String(localized: "Telefon pentru daune"),
                                                 detail: String(localized: "E pe poliță sau pe site-ul asigurătorului. Adaugă-l ca să suni dintr-o atingere.", comment: "Claim check: no claims phone."),
                                                 action: .editSection(assetID: asset.id)))
            }
            if let id = policy.deadlineID, let until = policy.validUntil {
                let valid = DueDayValidity.isValid(due: until, on: today)
                policyItems.append(ReadinessItem(
                    id: "claim.validity", status: valid ? .ok : .problem,
                    title: String(localized: "Valabilitatea poliței", comment: "Claim check: whether the policy is still valid."),
                    detail: valid
                        ? String(localized: "Valabilă până pe \(DosarFormat.longDay(until)).", comment: "Readiness: something valid until a day (feminine).")
                        : String(localized: "A expirat pe \(DosarFormat.longDay(until)). Sună totuși: asigurătorul îți spune ce acoperă.", comment: "Claim check: the policy has expired."),
                    action: .open(.obligation(id))
                ))
            } else {
                policyItems.append(notInBinder("claim.validity", title: String(localized: "Valabilitatea poliței", comment: "Claim check: whether the policy is still valid."),
                                               detail: String(localized: "Nu știu până când e valabilă. Adaugă termenul poliței.", comment: "Claim check: the policy's deadline isn't in the binder."),
                                               asset: asset, blueprintKey: policy.blueprintKey))
            }
        }
        let hasPolicy = asset.documentKinds.contains(.policy)
        policyItems.append(ReadinessItem(
            id: "claim.policyDocument", status: hasPolicy ? .ok : .missing, title: String(localized: "Polița"),
            detail: hasPolicy ? String(localized: "E în dosar, cu poză.", comment: "Claim check: the policy is filed.") : String(localized: "Fă o poză poliței, ca s-o ai la îndemână.", comment: "Claim check: no policy filed."),
            action: hasPolicy ? .open(.asset(asset.id)) : .addDocument(assetID: asset.id)
        ))

        let photos: [ReadinessItem]
        let papers: [ReadinessItem]
        if isCar {
            photos = [
                reminder("claim.photo.cars", String(localized: "Mașinile, cu numerele la vedere", comment: "Claim photo: the cars."),
                         String(localized: "Din față, din spate și din lateral, înainte să le mutați.", comment: "Claim photo: angles of the cars.")),
                reminder("claim.photo.damage", String(localized: "Fiecare avarie", comment: "Claim photo: each damage."),
                         String(localized: "De aproape și de departe, ca să se vadă unde e.", comment: "Claim photo: how to photograph damage.")),
                reminder("claim.photo.place", String(localized: "Locul", comment: "Claim photo: the place."),
                         String(localized: "Indicatoare, marcaje, urme pe carosabil.", comment: "Claim photo: what of the place.")),
                reminder("claim.photo.otherDriver", String(localized: "Actele celuilalt șofer", comment: "Claim photo: the other driver's papers."),
                         String(localized: "Talonul, permisul și polița RCA, dacă e și altă mașină.", comment: "Claim photo: which papers of the other driver.")),
                reminder("claim.photo.report", String(localized: "Constatarea amiabilă", comment: "Claim photo: the joint accident report."),
                         String(localized: "După ce o semnați amândoi. Dacă nu vă înțelegeți, sună la poliție.", comment: "Claim photo: the signed joint report.")),
            ]
            papers = [
                reminder("claim.paper.driver", String(localized: "Permisul de conducere și cartea de identitate", comment: "Claim paper: the driver's papers."),
                         String(localized: "Ale celui care conducea.", comment: "Claim paper: whose papers.")),
                reminder("claim.paper.car", String(localized: "Talonul și cartea de identitate a mașinii", comment: "Claim paper: the car's papers."),
                         String(localized: "Le cere asigurătorul la constatare.", comment: "Claim paper: why the car's papers.")),
                reminder("claim.paper.report", String(localized: "Constatarea amiabilă sau procesul-verbal de la poliție", comment: "Claim paper: the accident report."),
                         String(localized: "Originalul, nu doar poza.", comment: "Claim paper: the original report.")),
            ]
        } else {
            photos = [
                reminder("claim.photo.rooms", String(localized: "Fiecare cameră afectată", comment: "Claim photo: the rooms."),
                         String(localized: "Întâi de departe, apoi avariile de aproape.", comment: "Claim photo: how to photograph rooms.")),
                reminder("claim.photo.source", String(localized: "De unde a pornit", comment: "Claim photo: the cause."),
                         String(localized: "Țeava, acoperișul, geamul sau peretele.", comment: "Claim photo: what the cause can be.")),
                reminder("claim.photo.goods", String(localized: "Lucrurile stricate", comment: "Claim photo: damaged belongings."),
                         String(localized: "Înainte să arunci ceva, cu bonurile dacă le ai.", comment: "Claim photo: keep damaged things until photographed.")),
            ]
            papers = [
                reminder("claim.paper.id", String(localized: "Cartea de identitate", comment: "Claim paper: the ID card."),
                         String(localized: "A celui care are polița.", comment: "Claim paper: whose ID card.")),
                reminder("claim.paper.deed", String(localized: "Actul de proprietate", comment: "Claim paper: the property deed."),
                         String(localized: "Contractul sau extrasul de carte funciară.", comment: "Claim paper: which property paper.")),
                reminder("claim.paper.report", String(localized: "Procesul-verbal, dacă a venit cineva", comment: "Claim paper: an official report."),
                         String(localized: "De la pompieri, poliție sau administratorul blocului.", comment: "Claim paper: who writes the report.")),
            ]
        }

        return ReadinessChecklist(
            groups: [
                ReadinessGroup(id: "claim.policy", title: String(localized: "Polița", comment: "Claim group: the policy."), symbol: "doc.text.fill", items: policyItems),
                ReadinessGroup(id: "claim.photos", title: String(localized: "Ce fotografiezi", comment: "Claim group: what to photograph."), symbol: "camera.fill", items: photos),
                ReadinessGroup(id: "claim.papers", title: String(localized: "Acte de avut la îndemână", comment: "Claim group: documents to have ready."), symbol: "folder.fill", items: papers),
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
                let lastDone = obligation.history.first.map { CalendarDay($0.occurredAt, calendar: calendar) }
                let reading = ReadinessObligation(
                    id: obligation.id, due: obligation.dueDay(in: calendar), lastDone: lastDone, reference: obligation.reference,
                    title: obligation.title, kind: obligation.kind, amount: obligation.estimatedCost
                )
                if let key = obligation.blueprintKey { obligations[key] = reading } else { others.append(reading) }
            }
            let template = templates[asset.templateKey]
            return ReadinessAsset(
                id: asset.id, name: asset.name, templateKey: asset.templateKey,
                role: template?.behavior.role, parentId: asset.parent?.id, isSensitive: template?.isSensitive ?? false,
                values: asset.values, obligations: obligations, otherObligations: others,
                historyCount: (asset.history ?? []).count,
                documentKinds: (asset.attachments ?? []).filter { !$0.isArchived }.map(\.kind),
                facts: template.map { ReadinessFacts.of($0.definition) } ?? []
            )
        }
    }
}
