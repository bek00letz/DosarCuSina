import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// A deadline's reminders follow what they come from: when a value its blueprint's profile
/// depends on changes (a document's type, a pet's species), the deadline reminds as the new
/// value asks, its travel cut-off included, unless the person set its reminders themselves.
@MainActor
@Suite("A deadline's reminders follow its document")
struct DeadlineRemindersTests {
    let calendar = Calendar.bucharest
    let today = noon("2026-11-03")
    let expiry = CalendarDay("2031-08-12")

    private func profile(_ blueprintKey: String, in template: TemplateDefinition, _ field: String, _ value: String) throws -> ReminderProfile {
        try #require(template.blueprints.first { $0.key == blueprintKey }).reminders(for: FieldValues([field: .text(value)]))
    }

    private func documentProfile(_ type: String) throws -> ReminderProfile {
        try profile(BuiltInBlueprints.documentRenew, in: BuiltInTemplates.documents, DocumentType.typeFieldKey, type)
    }

    private func document(_ type: String, in context: ModelContext) throws -> (Asset, Obligation) {
        let documents = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.documents))
        let actions = AssetActions(context: context, calendar: calendar, now: { today })
        var values = FieldValues()
        values[DocumentType.typeFieldKey] = .text(type)
        values[DocumentFields.expiry] = .date(expiry)
        let asset = try actions.create(name: "Carte de identitate", template: documents, values: values,
                                       obligations: actions.plannedObligations(for: documents, values: values))
        return (asset, try #require(asset.activeObligations.first))
    }

    private func edit(_ asset: Asset, in context: ModelContext, _ change: (inout FieldValues) -> Void) throws {
        var values = asset.values
        change(&values)
        try AssetActions(context: context, calendar: calendar, now: { today }).update(asset, name: asset.name, values: values, notes: asset.notes)
    }

    // MARK: Documents

    @Test func changingTheTypeGivesTheDeadlineTheNewTypesReminders() throws {
        let context = try makeContext()
        let (card, renewal) = try document(DocumentType.idCard, in: context)
        #expect(try renewal.reminders == documentProfile(DocumentType.idCard))
        #expect(renewal.travelMarginDays == 0)

        // Editează: it was a passport all along.
        try edit(card, in: context) { $0[DocumentType.typeFieldKey] = .text(DocumentType.passport) }
        let passport = try documentProfile(DocumentType.passport)
        #expect(renewal.reminders == passport, "Its leads, consequence, grace, follow-up and cut-off")
        #expect(renewal.travelMarginDays == 180)
        #expect(renewal.updatedAt == today)

        // And back: the cut-off goes with the type.
        try edit(card, in: context) { $0[DocumentType.typeFieldKey] = .text(DocumentType.idCard) }
        #expect(try renewal.reminders == documentProfile(DocumentType.idCard))
        #expect(renewal.travelMarginDays == 0)
        #expect(!renewal.remindersCustomized)
    }

    /// The person's leads, grace and follow-up stay; the travel cut-off is a fact about the
    /// document, so it follows the type even here.
    @Test func anIdentityCardWithThePersonsRemindersGainsTheCutoffAsAPassport() throws {
        let context = try makeContext()
        let (card, renewal) = try document(DocumentType.idCard, in: context)
        let mine = ReminderProfile(leadDays: [120, 14], consequence: .legal, followUpAfterLapse: false)
        try ObligationActions(context: context, calendar: calendar, now: { today }).setReminders(renewal, mine)
        #expect(renewal.remindersCustomized)

        try edit(card, in: context) { $0[DocumentType.typeFieldKey] = .text(DocumentType.passport) }
        var withCutoff = mine
        withCutoff.travelMarginDays = try documentProfile(DocumentType.passport).travelMarginDays
        #expect(renewal.reminders == withCutoff, "The person's leads, grace and follow-up stay as set; only the cut-off is new")
        #expect(renewal.travelMarginDays == 180)
        #expect(renewal.remindersCustomized)
    }

    @Test func aPassportWithThePersonsRemindersLosesTheCutoffAsAnIdentityCard() throws {
        let context = try makeContext()
        let (passport, renewal) = try document(DocumentType.passport, in: context)
        #expect(renewal.travelMarginDays == 180)
        let mine = renewal.reminders.withLeadDays([200, 30])
        try ObligationActions(context: context, calendar: calendar, now: { today }).setReminders(renewal, mine)
        #expect(renewal.remindersCustomized)

        try edit(passport, in: context) { $0[DocumentType.typeFieldKey] = .text(DocumentType.idCard) }
        #expect(renewal.travelMarginDays == 0, "An identity card is good for travel until it expires")
        #expect(renewal.reminders.leadDays == [200, 30], "The leads stay, now counted from the expiry")
        #expect(renewal.reminders.graceDays == mine.graceDays)
        #expect(renewal.reminders.followUpAfterLapse == mine.followUpAfterLapse)
        #expect(renewal.reminders.consequence == mine.consequence)
        #expect(renewal.remindersCustomized)
        #expect(renewal.updatedAt == today)
    }

    @Test func aChangeThatKeepsTheCutoffLeavesThePersonsRemindersAlone() throws {
        let context = try makeContext()
        let (card, renewal) = try document(DocumentType.idCard, in: context)
        let mine = ReminderProfile(leadDays: [120, 14], consequence: .legal, followUpAfterLapse: false)
        try ObligationActions(context: context, calendar: calendar, now: { today }).setReminders(renewal, mine)
        try edit(card, in: context) { $0[DocumentType.typeFieldKey] = .text(DocumentType.drivingLicence) }
        #expect(renewal.reminders == mine)
    }

    // MARK: Pets

    @Test func aPetsSpeciesChangesItsRabiesReminders() throws {
        let context = try makeContext()
        let pets = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.pet))
        let actions = AssetActions(context: context, calendar: calendar, now: { today })
        var values = FieldValues()
        values["pet.species"] = .text(PetSpecies.cat)
        let planned = actions.plannedObligations(for: pets, values: values).map { plan -> PlannedObligation in
            var plan = plan
            plan.isSelected = plan.blueprint.key == BuiltInBlueprints.petRabies
            plan.firstDue = CalendarDay("2027-03-01")
            return plan
        }
        let pet = try actions.create(name: "Pisica", template: pets, values: values, obligations: planned)
        let rabies = try #require(pet.activeObligations.first { $0.blueprintKey == BuiltInBlueprints.petRabies })
        let cat = try profile(BuiltInBlueprints.petRabies, in: BuiltInTemplates.pet, "pet.species", PetSpecies.cat)
        let dog = try profile(BuiltInBlueprints.petRabies, in: BuiltInTemplates.pet, "pet.species", PetSpecies.dog)
        #expect(cat != dog)
        #expect(rabies.reminders == cat)

        try edit(pet, in: context) { $0["pet.species"] = .text(PetSpecies.dog) }
        #expect(rabies.reminders == dog, "A dog's rabies vaccine reminds as the law asks")
    }

    // MARK: Backups

    @Test func theFlagTravelsInABackup() throws {
        let source = try makeInMemoryContainer()
        let context = ModelContext(source)
        try TemplateStore(context: context).installBuiltIns()
        let (_, renewal) = try document(DocumentType.idCard, in: context)
        try ObligationActions(context: context, calendar: calendar, now: { today })
            .setReminders(renewal, ReminderProfile(leadDays: [100], consequence: .legal))
        let data = try DossierArchiveService(container: source, calendar: calendar).exportData(exportedAt: today)
        let entries = Dictionary(uniqueKeysWithValues: try DosarZipEngine.unpackArchive(data).map { ($0.path, $0.data) })
        let written = String(decoding: try #require(entries[DossierV3.Path.obligations]), as: UTF8.self)
        #expect(written.contains(#""remindersCustomized" : true"#))

        let target = try makeInMemoryContainer()
        try DossierArchiveService(container: target, calendar: calendar).importArchive(data, mode: .replace)
        let copy = try #require(try ModelContext(target).fetch(FetchDescriptor<Obligation>()).first { $0.id == renewal.id })
        #expect(copy.remindersCustomized)
        #expect(copy.reminders.leadDays == [100])
    }
}
