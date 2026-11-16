import Foundation
import Testing
@testable import DosarCuSina

/// The form for a category of one's own (`CustomCategoryForm`) in `docs/COPY_MATRIX.md`: the
/// words every category of one's own is asked in (`CustomCategoryWording`), then what each
/// counter its service may count by says (`CategorySwitches.Counter`).
extension CopyMatrixTests {
    /// The form's frame, the same whatever is chosen.
    static var customCategorySharedRows: [(String, String)] {
        typealias W = CustomCategoryWording
        return [
            ("Its name", "\(W.name), „\(W.namePrompt)” · \(W.symbol)"),
            ("What it keeps", "\(W.keeps) — \(W.documents): \(W.documentsHint) · \(W.bills): \(W.billsHint) · \(W.service): \(W.serviceHint)"),
            ("How the service counts (VoiceOver)", W.serviceCounter),
            ("How often, not a whole number", String(localized: W.wholeNumber)),
            ("Ține de…", "\(W.belongs) — \(W.belongsToNothing) · \(BelongingWording.option(.home)) — \(W.belongsFootnote) (\(W.belongsLabel))"),
            ("Its boxes", "\(W.boxes) — \(W.boxEach): \(W.boxEachHint) · \(W.boxAll): \(W.boxAllHint)"),
            ("Its line in Setări", [CategorySwitches(), CategorySwitches(hasDocuments: true, hasBills: true, service: .init(.kilometres))]
                .map(W.summary(of:)).joined(separator: " / ")),
        ]
    }

    /// What each counter says, once chosen.
    static var customCategoryCounterRows: [(String, String)] {
        CategorySwitches.Counter.allCases.map { counter in
            ("`\(counter.rawValue)`", "\(counter.title) — \(counter.subtitle) · \(counter.everyTitle) — \(counter.everyFootnote) · in Setări: \(counter.summary)")
        }
    }

    /// "## A category of one's own" of `docs/COPY_MATRIX.md`.
    static func customCategorySection() -> String {
        "## A category of one's own\n\nWhat `CustomCategoryForm` asks when a category of one's own is made („Altceva…”) "
            + "or changed in Setări, from `CustomCategoryWording` and each counter's words (`CategorySwitches.Counter`). "
            + "Its name is what one of its sections is called (`TemplateDefinition.sectionName`), so a new section's "
            + "name before anything is typed is the category's own; no gender is guessed from it.\n\n### What every category of one's own shares\n\n"
            + table(customCategorySharedRows) + "\n\n### What its service counts by\n\n" + table(customCategoryCounterRows) + "\n"
    }
}

@MainActor
@Suite("Copy matrix: a category of one's own")
struct CustomCategoryCopyRulesTests {
    @Test("No empty words, and vehicle words only where the service counts kilometres")
    func wordsFitTheirChoice() {
        for (place, words) in CopyMatrixTests.customCategorySharedRows + CopyMatrixTests.customCategoryCounterRows {
            #expect(!words.isEmpty && !words.contains("— —") && !words.contains("„”"), "\(place)")
        }
        for counter in CategorySwitches.Counter.allCases where counter != .kilometres {
            let words = CopyMatrixTests.tokens("\(counter.title) \(counter.subtitle) \(counter.everyTitle) \(counter.everyFootnote)")
            #expect(words.isDisjoint(with: CopyMatrixTests.vehicleWords), "\(counter): \(words.intersection(CopyMatrixTests.vehicleWords).sorted())")
        }
    }

    @Test("A category of one's own names its sections after itself, and no gender is guessed from its name")
    func ownCategoryNamesItsSections() throws {
        let own = try #require(try CopyMatrixTests.categories().first { $0.definition.key.hasPrefix(TemplateDefinition.customKeyPrefix) })
        #expect(own.definition.behavior.singular == nil, "Nothing of it is said in a gender („Carte” would read as „îl”)")
        #expect(own.definition.sectionName == own.definition.name)
    }
}
