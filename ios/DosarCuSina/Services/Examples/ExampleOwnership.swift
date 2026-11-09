import Foundation
import SwiftData

/// The person added something of their own (a deadline, a document, a history entry,
/// a reading, a section) to an example section. Nothing is saved: the screen asks
/// `question`, and on yes calls `ExampleDataService.adopt(sectionID:)` and saves again.
/// On no, nothing changes: the example stays as it was.
public struct ExampleSectionQuestion: StepQuestion, Equatable, Sendable {
    /// The topmost example the new thing would sit in: the one that becomes the person's.
    public let sectionID: UUID
    public let name: String
    public let gender: GrammaticalGender

    /// "Păstrezi „VW Golf” ca a ta?"
    public var question: String {
        switch gender {
        case .feminine: String(localized: "Păstrezi „\(name)” ca a ta?", comment: "Asked when the person adds something real to an example section whose noun is feminine (mașina, locuința).")
        case .masculineOrNeuter: String(localized: "Păstrezi „\(name)” ca al tău?", comment: "Asked when the person adds something real to an example section whose noun is masculine or neuter (actul, abonamentul).")
        }
    }

    /// What yes means, in plain words.
    public var explanation: String {
        switch gender {
        case .feminine: String(localized: "E un exemplu. Dacă o păstrezi, rămâne la tine cu tot ce e în ea și nu se mai șterge cu exemplele.")
        case .masculineOrNeuter: String(localized: "E un exemplu. Dacă îl păstrezi, rămâne la tine cu tot ce e în el și nu se mai șterge cu exemplele.")
        }
    }

    /// For a screen that doesn't ask: says what to do instead.
    public var errorDescription: String? {
        String(localized: "„\(name)” e un exemplu. Adaugă în altă secțiune sau păstrează exemplul ca al tău.")
    }
}

/// Grammatical gender of the noun one section of a category is, for words that agree with it.
public enum GrammaticalGender: String, Sendable, Hashable {
    /// Mașina, locuința, persoana.
    case feminine
    /// Actul, abonamentul, animalul. Romanian's default for a thing.
    case masculineOrNeuter
}

extension BuiltInTemplates {
    /// The gender of one section of each built-in category: a car is "mașina", a
    /// document "actul". A custom category reads as a thing ("al tău").
    static let sectionGender: [String: GrammaticalGender] = [
        Key.vehicle: .feminine, Key.home: .feminine, Key.bike: .feminine, Key.plants: .feminine, Key.member: .feminine,
    ]

    static func gender(ofSectionIn templateKey: String) -> GrammaticalGender {
        sectionGender[templateKey] ?? .masculineOrNeuter
    }
}

/// Only the example loader makes examples. Anything the person adds is theirs, and
/// it never lands inside an example without the person saying so. The actions that
/// create records (`AssetActions`, `ObligationActions`, `HistoryActions`,
/// `AttachmentActions`) all ask here.
@MainActor
public enum ExampleOwnership {
    /// The topmost example a record under `asset` would sit in, if any.
    public static func exampleSection(containing asset: Asset?) -> Asset? {
        var current = asset
        var topmost: Asset?
        var seen = Set<UUID>()
        while let node = current, seen.insert(node.id).inserted {
            if node.isExample { topmost = node }
            current = node.parent
        }
        return topmost
    }

    /// Whether the record about to be made under `asset` is an example: only when the
    /// example loader says so. Throws the question when it would be the person's own
    /// inside an example. It changes nothing, and every action asks it before its unit of
    /// work writes anything (`StepQuestion`).
    @discardableResult
    public static func requireReal(_ asset: Asset?, creatingExample: Bool = false) throws -> Bool {
        if creatingExample { return true }
        if let section = exampleSection(containing: asset) {
            throw ExampleSectionQuestion(sectionID: section.id, name: section.name,
                                         gender: BuiltInTemplates.gender(ofSectionIn: section.templateKey))
        }
        return false
    }
}
