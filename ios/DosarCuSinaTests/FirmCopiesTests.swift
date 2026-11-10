import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// Two copies of one firm meet by one rule (`FirmCopies`), whether the repair list joins a firm
/// kept twice or a backup's copy meets the phone's: a detail only one knows is never lost to the
/// other's newer copy. Every value is a placeholder.
@MainActor
@Suite("Two copies of a firm")
struct FirmCopiesTests {
    private func firm(_ context: ModelContext, _ name: String, phone: String? = nil, email: String? = nil, created: String) -> Provider {
        let firm = Provider(name: name, phone: phone)
        firm.email = email
        firm.createdAt = noon(created)
        context.insert(firm)
        return firm
    }

    @Test func aDetailOnlyOneCopyKnowsIsFilledInAndNothingIsEmptied() throws {
        let context = try makeContext()
        let kept = firm(context, "Instal Exemplu SRL", phone: "0700 000 001", created: "2026-01-01")
        kept.trades = ["instalator"]
        var other = FirmCopies.Details(trades: ["electrician", "instalator"], phone: "0700 000 002", email: "nume@exemplu.ro")
        other.taxID = "12345678"
        FirmCopies.gather(other, into: kept)
        #expect(kept.phone == "0700 000 001", "A detail the kept copy has stays")
        #expect(kept.email == "nume@exemplu.ro")
        #expect(kept.taxID == "12345678")
        #expect(kept.trades == ["electrician", "instalator"])
        FirmCopies.gather(FirmCopies.Details(), into: kept)
        #expect(kept.email == "nume@exemplu.ro", "An empty detail never empties one")
    }

    @Test func aJoinedFirmKeepsWhatItGatheredWhenAnotherPhonesNewerCopyComesIn() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let kept = firm(context, "Instal Exemplu SRL", created: "2026-01-01")
        let copy = firm(context, "Instal Exemplu SRL", phone: "0700 000 001", email: "nume@exemplu.ro", created: "2026-02-01")
        try UnitOfWork.save(context, now: noon("2026-02-01"))

        // The other phone's copy of the firm, before the join reached it: no phone, a newer note.
        let service = DossierArchiveService(container: container, calendar: .bucharest)
        var package = try DossierArchiveReader.read(try service.exportData(exportedAt: noon("2026-02-02")))
        let index = try #require(package.providers.firstIndex { $0.id == DossierV3.id(kept.id) })
        package.providers[index].notes = "Vine doar dimineața"
        package.providers[index].updatedAt = noon("2026-03-01")
        package.providers.removeAll { $0.id == DossierV3.id(copy.id) }

        let groups = try CaptureRepairs(context: context).duplicateProviderCandidates()
        try #require(groups.count == 1)
        try CaptureRepairs(context: context).mergeDuplicateProviders(groups)
        #expect(kept.phone == "0700 000 001")

        try service.importPackage(package, mode: .merge)
        let firms = try ModelContext(container).fetch(FetchDescriptor<Provider>())
        let after = try #require(firms.first { $0.id == kept.id })
        #expect(after.notes == "Vine doar dimineața", "The newer copy's change comes in")
        #expect(after.phone == "0700 000 001", "What the join filled in stays")
        #expect(after.email == "nume@exemplu.ro")
    }

    @Test func aNewerCopyHereTakesWhatOnlyTheBackupKnows() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let here = firm(context, "Instal Exemplu SRL", created: "2026-01-01")
        try UnitOfWork.save(context, now: noon("2026-01-01"))
        let service = DossierArchiveService(container: container, calendar: .bucharest)
        var package = try DossierArchiveReader.read(try service.exportData(exportedAt: noon("2026-01-02")))
        package.providers[0].email = "nume@exemplu.ro"
        package.providers[0].trades = ["electrician"]

        here.notes = "Sună înainte"
        try UnitOfWork.save(context, now: noon("2026-04-01"))
        try service.importPackage(package, mode: .merge)
        let after = try #require(try ModelContext(container).fetch(FetchDescriptor<Provider>()).first)
        #expect(after.notes == "Sună înainte", "The phone's newer copy stands")
        #expect(after.email == "nume@exemplu.ro", "What only the backup knew comes along")
        #expect(after.trades == ["electrician"])
    }
}
