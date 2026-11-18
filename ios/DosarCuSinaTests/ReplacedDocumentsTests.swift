import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// A personal document whose renewal was closed with „Am rezolvat” was replaced by a new one
/// (`Asset.wasReplaced`): it is expired whatever its printed date says, and it is no longer its
/// holder's current document. Every reader that picks, counts or orders documents reads that one
/// answer, and each is listed here:
///
/// - the trip's checks: a document a requirement asks for, the driving licence, the European
///   health card, the green card, and whether documents filed under no one travel
///   (`ReadinessEngine.documents(of:in:)`, through `ReadinessAsset.wasReplaced`);
/// - the person's hero, "Următorul act care expiră" (`DocumentPageFacts.nextToExpire`);
/// - every list of a person's documents (their Acte, "Vezi tot", the Acte box), the current ones
///   first (`DocumentPageFacts.currentFirst`);
/// - "Adaugă actul nou", offered until a current one of the same type is there
///   (`DocumentPageFacts.hasSuccessor`);
/// - Urmează, the widgets, the badge, reminders, Siri and Spotlight's deadlines, which read the
///   document's deadlines: its renewal is closed, so none of them shows it.
///
/// Read from every document, the replaced ones included, because a document's holder outlives
/// it: the traveller's citizenship (`Citizenship.of`) and who a policy insures, by the CNP on
/// their documents (`Policyholders`). Search and Spotlight's sections find every section, the
/// replaced ones too, as history: they say nothing about whether it is valid. The car's sale and a
/// claim pick no personal document.
@MainActor
@Suite("Replaced documents: never the person's current one")
struct ReplacedDocumentsTests {
    let calendar = Calendar.bucharest
    let today = "2026-11-17"

    // MARK: Fixtures

    /// Ion Popescu's old passport, printed valid until 2030 and replaced with „Am rezolvat” (it was
    /// lost); and, when `withNew`, the temporary passport that replaced it, valid until March 2028.
    struct Binder {
        var context: ModelContext
        var holder: Asset
        var old: Asset
        var new: Asset?
    }

    private func section(_ context: ModelContext, _ key: String, name: String, values: FieldValues = FieldValues(),
                         parent: Asset? = nil, at day: String) throws -> Asset {
        let template = try #require(try TemplateStore(context: context).template(forKey: key))
        let assets = AssetActions(context: context, calendar: calendar, now: { noon(day) })
        return try assets.create(name: name, template: template, values: values,
                                 obligations: assets.plannedObligations(for: template, values: values), parent: parent)
    }

    private func passport(_ context: ModelContext, holder: Asset, expiry: String, at day: String) throws -> Asset {
        var values = FieldValues()
        values[DocumentType.typeFieldKey] = .text(DocumentType.passport)
        values[DocumentFields.expiry] = .date(CalendarDay(expiry))
        return try section(context, BuiltInTemplates.Key.documents, name: "Pașaport", values: values, parent: holder, at: day)
    }

    private func binder(withNew: Bool = true) throws -> Binder {
        let context = try makeContext()
        let holder = try section(context, BuiltInTemplates.Key.member, name: "Ion Popescu", at: "2025-01-10")
        let old = try passport(context, holder: holder, expiry: "2030-05-01", at: "2025-01-10")
        let renewal = try #require(old.activeObligations.first { $0.blueprintKey == BuiltInBlueprints.documentRenew })
        try ObligationActions(context: context, calendar: calendar, now: { noon(self.today) }).complete(renewal, cycle: renewal.dueDay)
        #expect(old.wasReplaced, "„Am rezolvat” on its renewal replaced it")
        let new = withNew ? try passport(context, holder: holder, expiry: "2028-03-01", at: today) : nil
        return Binder(context: context, holder: holder, old: old, new: new)
    }

    /// A trip outside the EU next July: a passport counts until six months before it expires.
    private func tripOutsideTheEU(_ binder: Binder) throws -> [ReadinessItem] {
        let assets = try ReadinessAsset.fetchAll(in: binder.context, calendar: calendar)
        let plan = TripPlan(start: CalendarDay("2027-07-01"), end: CalendarDay("2027-07-20"), region: .outsideEU,
                            travellers: [.member(binder.holder.id)])
        return ReadinessEngine.check(.trip(plan), assets: assets, today: CalendarDay(today), calendar: calendar)
    }

    // MARK: The trip

    @Test("A replaced passport still valid by its printed date is not offered for a trip; the newer one is")
    func theNewerPassportGoes() throws {
        let binder = try binder()
        let new = try #require(binder.new)
        let check = try #require(try tripOutsideTheEU(binder)[id: "trip.passport.\(binder.holder.id)"])
        #expect(check.status == .ok)
        #expect(check.action == .open(.asset(new.id)), "The new passport, though the old one's printed date lasts longer")
    }

    @Test("With only the replaced passport, the trip asks for the new one")
    func onlyTheReplacedPassportIsMissing() throws {
        let binder = try binder(withNew: false)
        let check = try #require(try tripOutsideTheEU(binder)[id: "trip.passport.\(binder.holder.id)"])
        #expect(check.status == .missing)
        #expect(check.action == .addPersonalDocument(holderID: binder.holder.id), "Added for Ion, photo first")
    }

    @Test("The readiness snapshot carries the one answer")
    func theSnapshotCarriesIt() throws {
        let binder = try binder()
        let assets = try ReadinessAsset.fetchAll(in: binder.context, calendar: calendar)
        #expect(assets.first { $0.id == binder.old.id }?.wasReplaced == true)
        #expect(assets.first { $0.id == binder.old.id }?.isCurrentDocument == false)
        #expect(assets.first { $0.id == binder.new?.id }?.isCurrentDocument == true)
    }

    /// One reader of the trip's checks, and the item it gives for the traveller's document.
    enum TripReader: String, CaseIterable, CustomTestStringConvertible {
        case requirement, drivingLicence, healthCard, greenCard

        var testDescription: String { rawValue }

        var type: String {
            switch self {
            case .requirement: DocumentType.passport
            case .drivingLicence: DocumentType.drivingLicence
            case .healthCard: DocumentType.euHealthCard
            case .greenCard: DocumentType.greenCard
            }
        }

        /// Where the check is made: the health card only inside the EU, the rest outside it.
        var region: TripPlan.Region {
            self == .healthCard ? .europeanUnion : .outsideEU
        }

        func item(holder: ReadinessAsset, car: ReadinessAsset) -> String {
            switch self {
            case .requirement: "trip.passport.\(holder.id)"
            case .drivingLicence: "trip.licence.\(car.id)"
            case .healthCard: "trip.ehic.\(holder.id)"
            case .greenCard: "trip.greenCard.\(car.id)"
            }
        }
    }

    @Test("Every check of a trip skips a replaced document", arguments: TripReader.allCases)
    func everyTripCheckSkipsIt(_ reader: TripReader) {
        let ana = ReadinessAsset.member("Ana Popescu")
        let car = ReadinessAsset.car()
        let replaced = ReadinessAsset.personalDocument(reader.type, expires: "2031-01-01", holder: ana, wasReplaced: true)
        let current = ReadinessAsset.personalDocument(reader.type, expires: "2029-01-01", holder: ana)
        let plan = TripPlan(start: CalendarDay("2027-07-01"), end: CalendarDay("2027-07-20"), region: reader.region,
                            travellers: [.member(ana.id)], vehicles: [car.id])
        let id = reader.item(holder: ana, car: car)

        let both = ReadinessEngine.check(.trip(plan), assets: [ana, car, replaced, current], calendar: calendar)
        #expect(both[id: id]?.action == .open(.asset(current.id)), "The current one, never the replaced one")

        let alone = ReadinessEngine.check(.trip(plan), assets: [ana, car, replaced], calendar: calendar)
        #expect(alone[id: id]?.action != .open(.asset(replaced.id)), "A replaced one alone is as if it weren't there")
    }

    @Test("Documents filed under no one travel only while one of them is still current")
    func replacedUnfiledDocumentsDoNotTravel() {
        let replaced = ReadinessAsset.personalDocument(DocumentType.passport, expires: "2031-01-01", wasReplaced: true)
        #expect(!ReadinessEngine.tripCandidates(in: [replaced]).travellers.contains { $0.traveller == .unfiled })
        let current = ReadinessAsset.personalDocument(DocumentType.idCard, expires: "2031-01-01")
        #expect(ReadinessEngine.tripCandidates(in: [replaced, current]).travellers.contains { $0.traveller == .unfiled })
    }

    @Test("A replaced document still says whose citizenship its holder has")
    func citizenshipOutlivesTheDocument() {
        let ana = ReadinessAsset.member("Ana Popescu", citizenship: nil)
        let replaced = ReadinessAsset.personalDocument(DocumentType.passport, expires: "2031-01-01", holder: ana, nationality: "ROU", wasReplaced: true)
        #expect(ReadinessEngine.citizenships(of: .member(ana.id), in: [ana, replaced]) == [Citizenship.romania],
                "Not asked again while the new one isn't in the binder yet")
    }

    // MARK: The person's page and lists

    @Test("The person's next document to expire is never a replaced one")
    func theHeroSkipsIt() throws {
        let binder = try binder()
        let template = try #require(try TemplateStore(context: binder.context).template(forKey: BuiltInTemplates.Key.documents))
        let expiry: (Asset) -> CalendarDay? = { AssetFacts.expiry($0.values, template: template.definition) }
        let documents = binder.holder.children ?? []
        #expect(DocumentPageFacts.nextToExpire(documents, expiry: expiry)?.document.id == binder.new?.id)
        #expect(DocumentPageFacts.nextToExpire([binder.old], expiry: expiry) == nil, "Expired already: nothing next to expire")
    }

    @Test("Every list of a person's documents shows the current ones first, the replaced ones after")
    func listsShowItLast() throws {
        let binder = try binder()
        // By when they were made, the old one would come first.
        let byAge = DocumentPageFacts.currentFirst([binder.old, try #require(binder.new)]) { $0.createdAt < $1.createdAt }
        #expect(byAge.map(\.id) == [binder.new?.id, binder.old.id])

        // The Acte box: soonest expiry first, the replaced one after them, even printed sooner.
        binder.old.values[DocumentFields.expiry] = .date(CalendarDay("2027-01-01"))
        let groups = try DocumentHolders.groups(in: binder.context, calendar: calendar)
        let ion = try #require(groups.first { $0.holder?.id == binder.holder.id })
        #expect(ion.documents.map(\.id) == [binder.new?.id, binder.old.id])
    }

    @Test("„Adaugă actul nou” is offered until a current one of the same type is there")
    func aReplacedOneIsNoSuccessor() throws {
        let binder = try binder(withNew: false)
        #expect(!DocumentPageFacts.hasSuccessor(binder.old))
        _ = try passport(binder.context, holder: binder.holder, expiry: "2036-11-01", at: today)
        #expect(DocumentPageFacts.hasSuccessor(binder.old))
    }

    // MARK: Outside the page

    @Test("Urmează, the widgets, reminders and Spotlight show nothing of a replaced document")
    func nothingOutsideShowsIt() throws {
        let binder = try binder()
        let snapshots = try ObligationSnapshot.fetchForOutside(in: binder.context, calendar: calendar)
        let open = snapshots.filter { $0.assetId == binder.old.id && ($0.status == .active || $0.status == .paused) }
        #expect(open.isEmpty, "Its renewal is closed")
        let digest = AttentionModel.digest(snapshots, now: noon(today), calendar: calendar)
        let shown = digest.now.map(\.obligation.assetId) + digest.soon.flatMap { $0.entries.map(\.obligation.assetId) }
        #expect(!shown.contains(binder.old.id))
        #expect(snapshots.contains { $0.assetId == binder.new?.id && $0.status == .active }, "The new one reminds")
    }
}
