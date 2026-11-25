import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// Until iCloud's copies of a category are joined (`RecordsMeet` waits for the binder and for
/// each copy to be named), a device holds two records with one key: every list a person sees
/// shows the category once (`CategoryTemplate.oncePerKey`), the same copy every lookup by key
/// reads. Every value is a placeholder.
@MainActor
@Suite("A category's copies show once")
struct CategoryCopiesShownOnceTests {
    /// The catalog installed here, and a second copy of each built-in as iCloud brings another
    /// device's, made later.
    private func twoCopiesOfEach() throws -> (ModelContext, [CategoryTemplate]) {
        let context = try makeContext()
        try TemplateStore(context: context).installBuiltIns()
        for template in try TemplateStore(context: context).all() where template.isBuiltIn {
            let copy = CategoryTemplate(definition: template.definition, isBuiltIn: true, homeOrder: template.homeOrder)
            copy.createdAt = template.createdAt.addingTimeInterval(60)
            context.insert(copy)
        }
        try context.save()
        return (context, try context.fetch(FetchDescriptor<CategoryTemplate>(sortBy: [SortDescriptor(\.homeOrder)])))
    }

    @Test func eachCategoryShowsOnceAndAsTheCopyLookupsRead() throws {
        let (context, all) = try twoCopiesOfEach()
        let keys = Set(all.map(\.key))
        #expect(all.count == keys.count * 2)
        let once = CategoryTemplate.oncePerKey(all)
        #expect(once.count == keys.count)
        #expect(once.map(\.key) == all.map(\.key).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }, "In the order given")
        let byKey = try TemplateStore(context: context).templatesByKey()
        #expect(once.allSatisfy { byKey[$0.key] === $0 }, "The copy every lookup by key reads")
    }

    @Test func addingASectionOffersEachCategoryOnce() throws {
        let (_, all) = try twoCopiesOfEach()
        let offers = SectionOffers(all)
        let keys = offers.inOrder.map(\.key)
        #expect(keys.count == Set(keys).count)
    }
}
