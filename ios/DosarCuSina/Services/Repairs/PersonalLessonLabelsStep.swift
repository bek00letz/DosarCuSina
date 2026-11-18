import Foundation
import SwiftData

// MARK: - Lessons whose label is a value of the household's

/// Before capture refused a label that holds what the binder keeps that names the household
/// (`HouseholdValues`: a person's name, a home's address or locality, a plate), a lesson could
/// keep one as the label an issuer prints a value under. Each such lesson is offered to be
/// forgotten, in plain words; an issuer learned of from a locked category's papers isn't named
/// (`IssuerLessons.isProtected`). It asks, because it changes what Settings › Ce am învățat lists.
struct PersonalLessonLabelsStep: DataRepairStep {
    static let id = DataRepairStepID.personalLessonLabels
    var title: String { String(localized: "Ce am învățat de pe documente", comment: "Repair group: labels capture learned that hold a name, an address or a plate of the household.") }
    var applyTitle: String { String(localized: "Uită eticheta", comment: "Applies one repair: forget a label capture learned that holds a value of the household.") }

    /// The lessons whose label holds a word of the household's.
    static func candidates(in context: ModelContext) throws -> [IssuerLesson] {
        let household = try HouseholdValues.words(in: context)
        guard !household.isEmpty else { return [] }
        return try context.fetch(FetchDescriptor<IssuerLesson>())
            .filter { !$0.isDeleted && RomanianText.words($0.label).contains { household.contains(String($0)) } }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    func findings(_ scan: inout DataRepairScan) throws -> [DataRepairFinding] {
        let candidates = try Self.candidates(in: scan.context)
        guard !candidates.isEmpty else { return [] }
        let locks = BinderLocks.read(in: scan.context)
        return candidates.map { lesson in
            let message: String
            if IssuerLessons.isProtected(lesson, locks: locks) || lesson.issuerName.isEmpty {
                message = String(localized: "De pe documentul unei firme am ținut minte o etichetă care conține un nume, o adresă sau un număr de mașină din dosarul tău. O uit?",
                                 comment: "Repair: a label capture learned holds a value of the household; the issuer isn't named (a locked category's paper, or no name).")
            } else {
                message = String(localized: "De pe documentele „\(lesson.issuerName)” am ținut minte eticheta „\(lesson.label)”, care conține un nume, o adresă sau un număr de mașină din dosarul tău. O uit?",
                                 comment: "Repair: a label capture learned of an issuer's papers holds a value of the household (a name, an address, a plate).")
            }
            return DataRepairFinding(id: "\(Self.id.rawValue):\(lesson.id.uuidString)", step: Self.id, message: message,
                                     subject: .issuerLesson(id: lesson.id))
        }
    }

    func apply(_ findings: [DataRepairFinding], in context: ModelContext, calendar: Calendar) throws {
        let still = Dictionary(try Self.candidates(in: context).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for finding in findings {
            guard case .issuerLesson(let id) = finding.subject, let lesson = still[id] else { continue }
            context.delete(lesson)
        }
    }
}
