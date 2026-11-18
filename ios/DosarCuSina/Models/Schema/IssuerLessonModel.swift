import Foundation
import SwiftData

extension DosarSchemaV17 {
    /// One thing capture learned from what the person saved: the issuer of a kind of paper
    /// prints one of its values under one label ("ENGIE Romania S.A. prints a bill's due date
    /// under „Ultima zi de plată”"). The phone's own reader is told the label the next time it
    /// reads a paper of that issuer (`CaptureLessons`), so a paper a model once had to read is
    /// read on the phone alone.
    ///
    /// It holds an issuer's words and layout only, never anything of the person's: the label
    /// is a few words with no digits that hold none of the values saved (`CaptureLessonLearner`).
    /// It syncs and travels in backups like the rest of the binder.
    ///
    /// The id is the lesson's own (`CaptureLesson.id`): the same issuer, kind, field and label
    /// give the same id on every device, so two devices that learn the same lesson make one
    /// record once their copies meet (`RecordsMeet`). Version 16; its category, version 17.
    @Model
    public final class IssuerLesson {
        public var id: UUID = UUID()
        /// Which copy of this record it is (`Asset.copyID`).
        public var copyID: UUID?
        /// Who issued the papers: its CUI, else its name as the page prints it (`IssuerKey`).
        public var issuerKey: String = ""
        /// The issuer's name, as the person last saved it, for Settings.
        public var issuerName: String = ""
        /// The kind of paper (`CaptureDocumentKind`'s raw value).
        public var kindRaw: String = ""
        /// The value it prints under the label (`CaptureFieldKey`'s raw value).
        public var fieldKey: String = ""
        /// The label, as printed: a few words, no digits.
        public var label: String = ""
        /// The category of the section the paper it was learned from was filed in (a
        /// `CategoryTemplate` key), so what was learned from a locked category's papers stays
        /// behind its lock (`IssuerLessons.isProtected`). Nil for a lesson learned before
        /// version 17, or from a paper filed in no section.
        public var categoryKey: String?
        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()

        public init(_ lesson: CaptureLesson, issuerName: String, categoryKey: String? = nil) {
            self.copyID = UUID()
            self.id = lesson.id
            self.issuerKey = lesson.issuer.rawValue
            self.issuerName = issuerName
            self.kindRaw = lesson.kind.rawValue
            self.fieldKey = lesson.field.rawValue
            self.label = lesson.label
            self.categoryKey = categoryKey
        }

        /// The lesson it keeps; nil for one a newer build wrote that this one can't read (a kind
        /// it doesn't know), which stays as it is.
        public var lesson: CaptureLesson? {
            guard let kind = CaptureDocumentKind(rawValue: kindRaw), !issuerKey.isEmpty, !fieldKey.isEmpty, !label.isEmpty else { return nil }
            return CaptureLesson(issuer: IssuerKey(rawValue: issuerKey), kind: kind, field: CaptureFieldKey(rawValue: fieldKey), label: label)
        }
    }
}
