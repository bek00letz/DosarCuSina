import Foundation
import Testing
@testable import DosarCuSina

@Suite("Binder wording")
struct BinderWordingTests {
    let calendar = Calendar.bucharest
    let ro = Locale(identifier: "ro_RO")

    @Test("Years and months use the catalog's plural forms", arguments: [
        (1, "un an", "o lună"), (2, "2 ani", "2 luni"), (19, "19 ani", "19 luni"), (20, "20 de ani", "20 de luni"),
    ])
    func calendarCounts(count: Int, years: String, months: String) {
        #expect(CalendarCount.years(count) == years)
        #expect(CalendarCount.months(count) == months)
    }

    @Test func agesReadNaturally() {
        let today = CalendarDay("2026-11-02")
        #expect(AgeWording.text(born: CalendarDay("2023-06-10"), today: today, calendar: calendar) == "3 ani")
        #expect(AgeWording.text(born: CalendarDay("2025-07-01"), today: today, calendar: calendar) == "un an și 4 luni")
        #expect(AgeWording.text(born: CalendarDay("2026-06-01"), today: today, calendar: calendar) == "5 luni")
        #expect(AgeWording.text(born: CalendarDay("2026-10-20"), today: today, calendar: calendar) == "sub o lună")
        #expect(AgeWording.text(born: CalendarDay("2027-01-01"), today: today, calendar: calendar) == nil)
    }

    @Test func visitButtonFollowsTheCategory() {
        #expect(VisitWording.forTemplate(key: "vehicle", heroStyle: .vehicle).title == "Am fost la service")
        #expect(VisitWording.forTemplate(key: "bike", heroStyle: .standard).title == "Am fost la service")
        #expect(VisitWording.forTemplate(key: "pet", heroStyle: .pet).title == "Am fost la veterinar")
        #expect(VisitWording.forTemplate(key: "home", heroStyle: .home).title == "Am chemat un meseriaș")
        #expect(VisitWording.forTemplate(key: "health", heroStyle: .standard).title == "Am fost la medic")
        #expect(VisitWording.forTemplate(key: "custom.x", heroStyle: .standard).title == "Am făcut o lucrare")
    }

    @Test func componentLineShowsDistanceDateAndPrice() {
        let occurrence = ComponentOccurrence(
            entryId: UUID(), componentKey: "brakes.padsFront", name: "Plăcuțe frână față",
            date: noon("2025-03-14", calendar: calendar), metricAtTime: 124_300, metricSince: 18_200, daysSince: 600,
            cost: Money(420), partBrandOrCode: nil, supplierName: nil, providerNames: [], providerIds: []
        )
        let line = ComponentLine.detail(occurrence, unit: "km", locale: ro, calendar: calendar)
        #expect(line.hasPrefix("acum 18.200 km · 14 mar. 2025 · 420"))
        #expect(line.contains("RON") || line.contains("lei"))
    }

    @Test func moneyIsSummedPerCurrencyAndForTheLastYear() {
        let now = noon("2026-11-02", calendar: calendar)
        let summary = MoneySummary.make(entries: [
            (noon("2026-10-01", calendar: calendar), MoneyTotals([Money(300)])),
            (noon("2024-01-01", calendar: calendar), MoneyTotals([Money(100)])),
            (noon("2026-09-01", calendar: calendar), MoneyTotals([Money(50, currency: "EUR")])),
            (noon("2026-08-01", calendar: calendar), MoneyTotals()),
        ], now: now, calendar: calendar)
        #expect(summary.allTime.amount(in: "RON") == 400)
        #expect(summary.lastTwelveMonths.amount(in: "RON") == 300)
        #expect(summary.lastTwelveMonths.amount(in: "EUR") == 50)
        #expect(summary.jobCount == 3)
    }

    @Test func heroSubtitleJoinsNamesAndKeepsYearsPlain() {
        var values = FieldValues()
        values["vehicle.make"] = .text("Volkswagen")
        values["vehicle.model"] = .text("Golf")
        values["vehicle.year"] = .number(2018)
        #expect(HeroFacts.subtitle(values, definition: BuiltInTemplates.vehicle, locale: ro) == "Volkswagen Golf · 2018")
        #expect(HeroFacts.subtitle(FieldValues(), definition: BuiltInTemplates.vehicle, locale: ro) == nil)
    }

    @Test func childSummaryShowsRentAndContractEnd() {
        var values = FieldValues()
        values["tenancy.rent"] = .money(Money(2000))
        values["tenancy.end"] = .date(CalendarDay("2027-08-31"))
        let summary = ChildSummary.make(values, definition: BuiltInTemplates.tenancy, locale: ro)
        #expect(summary.endDay == CalendarDay("2027-08-31"))
        #expect(summary.line?.contains("până la 31 aug. 2027") == true)
        #expect(summary.line?.contains("2.000") == true)

        var product = FieldValues()
        product["purchase.warrantyUntil"] = .date(CalendarDay("2028-01-15"))
        let warranty = ChildSummary.make(product, definition: BuiltInTemplates.purchase, locale: ro)
        #expect(warranty.line?.contains("garanție până la 15 ian. 2028") == true || warranty.line?.contains("până la 15 ian. 2028") == true)
    }

    @Test func keyTestResultsTellOfflineApartFromABadKey() {
        #expect(AIProviderError(transport: URLError(.notConnectedToInternet)) == .offline)
        #expect(AIProviderError(transport: URLError(.timedOut)) == .offline)
        #expect(AIProviderError(transport: URLError(.badServerResponse)) == .badResponse)
        let offline = AIKeyWording.message(.failed(.offline), provider: .gemini) ?? ""
        let invalid = AIKeyWording.message(.failed(.invalidKey), provider: .gemini) ?? ""
        #expect(offline.contains("internet"))
        #expect(invalid.contains("cheia"))
        #expect(offline != invalid)
    }

    @Test func backupSummaryCountsWithPlurals() {
        let summary = ArchiveSummary(
            schemaVersion: 3, platform: "ios", exportedAt: noon("2026-11-02", calendar: calendar),
            counts: .init(templates: 13, assets: 1, obligations: 20, historyEntries: 4, serviceItems: 2, providers: 1, measurements: 0, attachments: 3)
        )
        let text = BackupWording.summary(summary, locale: ro)
        #expect(text.contains("o secțiune"))
        #expect(text.contains("20 de termene"))
        #expect(text.contains("3 documente"))
    }

    @Test func unlockFeedbackSaysWhatHappened() {
        #expect(UnlockFeedback(.success).message == nil)
        #expect(UnlockFeedback(.cancelled).message != nil)
        #expect(UnlockFeedback(.failed).message != UnlockFeedback(.cancelled).message)
    }
}

@Suite("Search highlighting and recent searches")
struct SearchSupportTests {
    @Test func highlightsWordStartsIgnoringDiacritics() {
        let text = "Poliță RCA pentru VW Golf"
        let ranges = SearchHighlighter.ranges(in: text, query: "polita golf")
        #expect(ranges.map { String(text[$0]) } == ["Poliță", "Golf"])
    }

    @Test func highlightsOnlyThePrefixThatMatched() {
        let text = "Plăcuțele de frână"
        let ranges = SearchHighlighter.ranges(in: text, query: "placu")
        #expect(ranges.map { String(text[$0]) } == ["Plăcu"])
        #expect(SearchHighlighter.ranges(in: text, query: "  ").isEmpty)
        #expect(SearchHighlighter.ranges(in: text, query: "ulei").isEmpty)
    }

    @Test func recentSearchesMoveToTheTopWithoutDuplicates() {
        var items: [String] = []
        items = RecentSearches.adding("RCA", to: items)
        items = RecentSearches.adding("instalator", to: items)
        items = RecentSearches.adding("rca", to: items)
        #expect(items == ["rca", "instalator"])
        items = RecentSearches.adding("   ", to: items)
        #expect(items == ["rca", "instalator"])
        let many = (0..<20).reduce([String]()) { RecentSearches.adding("q\($1)", to: $0) }
        #expect(many.count == RecentSearches.limit)
        #expect(many.first == "q19")
    }

    @Test func resultsAreGroupedInDisplayOrder() {
        func result(_ kind: SearchResultKind) -> SearchResult {
            SearchResult(document: SearchDocument(id: UUID().uuidString, kind: kind, title: "x", subtitle: nil, route: .home, fields: []), score: 1, snippet: nil)
        }
        let groups = SearchGroups.make([result(.provider), result(.asset), result(.provider), result(.document)])
        #expect(groups.map(\.kind) == [.asset, .document, .provider])
        #expect(groups.last?.results.count == 2)
    }
}
