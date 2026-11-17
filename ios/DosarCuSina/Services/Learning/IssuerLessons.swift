import Foundation
import SwiftData

/// What capture learned of each issuer's papers, kept in the binder: the one path to read the
/// lessons for a capture (`book`), to keep what a saved paper taught (`record`, in the filing's
/// own step), to forget an issuer (`forget`, with its undo) and to drop lessons that contradict
/// each other (`settle`, the app's own step).
///
/// The lessons sync with the binder and travel in backups. Two devices that learn the same
/// lesson make two records with the same id (`CaptureLesson.id`), joined by `RecordsMeet`; two
/// that learn one label for two different values of one issuer's paper contradict each other,
/// and `settle` removes both, the same on every device. What is learned from one paper stands
/// beside what is learned from another: the union of everything that agrees.
@MainActor
struct IssuerLessons {
    let context: ModelContext
    var now: () -> Date = { Date() }

    // MARK: Reading

    /// Every lesson the binder keeps, as a capture's readers are told them.
    func book() throws -> LessonBook {
        LessonBook(try records().compactMap(\.lesson))
    }

    /// The lessons of the binder the app runs on, for a capture about to read. A binder that
    /// can't be read gives none: the page is read as it would be with nothing learned.
    static func book(in container: ModelContainer?) -> LessonBook {
        guard let container else { return .empty }
        do {
            return try IssuerLessons(context: container.mainContext).book()
        } catch {
            PersistenceLog.failed("Reading what capture learned", error)
            return .empty
        }
    }

    private func records() throws -> [IssuerLesson] {
        try context.fetch(FetchDescriptor<IssuerLesson>()).filter { !$0.isDeleted }
    }

    // MARK: Learning

    /// Keeps what a saved paper taught, as part of the step that files it: inside the filer's
    /// unit, so the paper and its lessons are kept together, and "Anulează" takes both back.
    /// A lesson already kept takes the issuer's name as saved now; a lesson shown wrong goes.
    func record(_ outcome: CaptureLessonLearner.Outcome) throws {
        try UnitOfWork.perform(in: context, now: now()) {
            let kept = try records()
            let forgotten = Set(outcome.forgotten.map(\.id))
            for record in kept where forgotten.contains(record.id) {
                context.delete(record)
            }
            for lesson in outcome.learned {
                if let here = kept.first(where: { $0.id == lesson.id && !$0.isDeleted }) {
                    if !outcome.issuerName.isEmpty, here.issuerName != outcome.issuerName { here.issuerName = outcome.issuerName }
                } else {
                    context.insert(IssuerLesson(lesson, issuerName: outcome.issuerName))
                }
            }
            // One name for the issuer, the one saved last.
            if !outcome.issuerName.isEmpty {
                for record in kept where record.issuerKey == outcome.issuer.rawValue && !record.isDeleted && record.issuerName != outcome.issuerName {
                    record.issuerName = outcome.issuerName
                }
            }
            try UnitOfWork.save(context, now: now())
        }
    }

    // MARK: Forgetting

    /// Forgets everything learned of one issuer, as one step the person can take back.
    func forget(_ issuer: IssuerKey) throws -> UndoReceipt {
        try UnitOfWork.performUndoable(in: context, now: now()) {
            for record in try records() where record.issuerKey == issuer.rawValue {
                context.delete(record)
            }
            try UnitOfWork.save(context, now: now())
        }.receipt
    }

    // MARK: Settling

    /// The app's own step: lessons that give one label of one issuer's paper to two different
    /// values (two devices, or a backup, that learned differently) all go, on every device alike.
    /// Run where copies of records meet: at launch, after every synced change and every import.
    /// Returns whether anything changed.
    @discardableResult
    static func settle(in context: ModelContext) throws -> Bool {
        guard try !contradicted(in: context).isEmpty else { return false }
        return try UnitOfWork.perform(in: context, origin: .app) {
            try dropContradicted(in: context)
        }
    }

    /// Deletes the lessons that contradict each other, inside a step already open: `settle`'s, or a
    /// backup's import (`DossierImporter`), which runs away from the main thread. Saves nothing.
    @discardableResult
    nonisolated static func dropContradicted(in context: ModelContext) throws -> Bool {
        let out = try contradicted(in: context)
        for record in out { context.delete(record) }
        return !out.isEmpty
    }

    nonisolated private static func contradicted(in context: ModelContext) throws -> [IssuerLesson] {
        let records = try context.fetch(FetchDescriptor<IssuerLesson>()).filter { !$0.isDeleted }
        let out = Set(LessonBook.contradicted(records.compactMap(\.lesson)).map(\.id))
        return records.filter { out.contains($0.id) }
    }

    // MARK: Settings

    /// One issuer the binder learned of, for Settings: its name and what it prints where.
    struct Issuer: Identifiable, Hashable {
        let key: IssuerKey
        let name: String
        /// Each learned value and its label, in the order the review shows values.
        let lessons: [CaptureLesson]

        var id: String { key.rawValue }
    }

    /// The issuers `records` teach of, by name; a lesson another contradicts isn't shown, as it
    /// isn't read. A record a newer build wrote that this one can't read is left out.
    static func issuers(_ records: [IssuerLesson]) -> [Issuer] {
        let lessons = records.filter { !$0.isDeleted }.compactMap { record in record.lesson.map { (record, $0) } }
        let out = LessonBook.contradicted(lessons.map(\.1))
        let byIssuer = Dictionary(grouping: lessons.filter { !out.contains($0.1) }, by: \.1.issuer)
        let order = Dictionary(CaptureMapping.reviewOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return byIssuer.map { key, entries in
            let newest = entries.max { $0.0.updatedAt < $1.0.updatedAt }?.0
            let name = newest?.issuerName.isEmpty == false ? newest?.issuerName ?? "" : IssuerWording.unnamed(key)
            let sorted = entries.map(\.1).sorted { lhs, rhs in
                let left = order[lhs.field] ?? Int.max, right = order[rhs.field] ?? Int.max
                if left != right { return left < right }
                if lhs.kind != rhs.kind { return lhs.kind.rawValue < rhs.kind.rawValue }
                return lhs.label < rhs.label
            }
            return Issuer(key: key, name: name, lessons: sorted)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// How Settings says what was learned, in plain words.
enum IssuerWording {
    /// An issuer whose name wasn't saved: by its CUI („Firma cu CUI 12345674”).
    static func unnamed(_ key: IssuerKey) -> String {
        if let taxID = key.taxID {
            return String(localized: "Firma cu CUI \(taxID)", comment: "Settings: an issuer capture learned of, known only by its tax ID.")
        }
        return String(localized: "Firmă fără nume", comment: "Settings: an issuer capture learned of whose name wasn't saved.")
    }

    /// One lesson, in plain words: „Data scadenței: „Ultima zi de plată””, the value and the label
    /// the issuer prints it under.
    static func lesson(_ lesson: CaptureLesson) -> String {
        String(localized: "\(CaptureMapping.label(for: lesson.field)): „\(lesson.label)”",
               comment: "Settings: a value and the label an issuer prints it under, e.g. 'Data scadenței: „Ultima zi de plată”'.")
    }

    /// The row's status in Settings' list: „Nimic încă”, „De la o firmă”, „De la 3 firme”.
    static func status(issuers count: Int) -> String {
        guard count > 0 else {
            return String(localized: "Nimic încă", comment: "Settings row: capture hasn't learned anything from saved papers yet.")
        }
        return String(localized: "De la \(count) firme", comment: "Settings row: how many issuers capture learned from, with Romanian plural forms (de la o firmă, de la 2 firme, de la 20 de firme).")
    }
}
