import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import DosarCuSina

/// The reminder settings sheet ("Schimbă când te anunț") offers "Revino la cele obișnuite"
/// only for a deadline whose reminders the person set and that differ from the usual ones.
@MainActor
@Suite("Reminder settings")
struct ReminderSettingsTests {
    let calendar = Calendar.bucharest
    let today = noon("2026-11-03")

    private func passport(in context: ModelContext) throws -> Obligation {
        let documents = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.documents))
        let actions = AssetActions(context: context, calendar: calendar, now: { today })
        var values = FieldValues()
        values[DocumentType.typeFieldKey] = .text(DocumentType.passport)
        values[DocumentFields.expiry] = .date(CalendarDay("2031-08-12"))
        let asset = try actions.create(name: "Pașaport", template: documents, values: values,
                                       obligations: actions.plannedObligations(for: documents, values: values))
        return try #require(asset.activeObligations.first)
    }

    private func height(of form: ReminderSettingsForm, at typeSize: DynamicTypeSize = .large) -> CGFloat {
        let host = UIHostingController(rootView: form.environment(\.dynamicTypeSize, typeSize))
        return host.sizeThatFits(in: CGSize(width: 375, height: .greatestFiniteMagnitude)).height
    }

    @Test func theSheetOffersTheUsualOnesOnlyOnceThePersonChangedThem() throws {
        let context = try makeContext()
        let renewal = try passport(in: context)
        let actions = ObligationActions(context: context, calendar: calendar, now: { today })
        let usual = renewal.reminders
        #expect(ReminderSettings(obligation: renewal, in: context).usual == nil, "The usual ones: nothing to go back to")

        try actions.setReminders(renewal, usual.withLeadDays([14]))
        let changed = ReminderSettings(obligation: renewal, in: context)
        #expect(changed.usual == usual)
        #expect(changed.profile.leadDays == [14])

        _ = try #require(try actions.restoreUsualReminders(renewal))
        #expect(ReminderSettings(obligation: renewal, in: context).usual == nil, "Back to the usual ones: the row goes")
    }

    @Test(arguments: [DynamicTypeSize.large, .accessibility5])
    func theRowIsDrawnOnlyWhenOfferedAndIsATapTarget(typeSize: DynamicTypeSize) throws {
        let context = try makeContext()
        let renewal = try passport(in: context)
        let usual = renewal.reminders
        let mine = usual.withLeadDays([14])
        let without = height(of: ReminderSettingsForm(settings: ReminderSettings(profile: mine, usual: nil)), at: typeSize)
        let with = height(of: ReminderSettingsForm(settings: ReminderSettings(profile: mine, usual: usual)), at: typeSize)
        #expect(with - without >= DS.Control.minimumHitTarget, "The row is there, and at least 44 pt tall")
    }
}
