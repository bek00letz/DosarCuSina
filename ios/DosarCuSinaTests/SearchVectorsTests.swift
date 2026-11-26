import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// What Caută finds and keeps, run over inputs chosen to bite and written to
/// `shared/test-vectors/search/`, one file per rule: how the index matches and ranks
/// (`SearchIndex`), what it takes out of what it keeps and what may be remembered or shown
/// outside the app (`SearchPrivacy`, `RecentSearches.adding`), and what each record of a binder
/// gives the index (`SearchIndexBuilder`). The Android app's tests read the same files and must
/// give the same answers (docs/ANDROID_PLAN.md, "How parity is kept"). A sibling of
/// `TextVectorsTests`, with a folder of its own.
///
/// Placeholder data only: the networks' published test card numbers, the made-up CNP with county
/// code 99, IBANs from the specifications, and a microchip built when the test runs
/// (`TextVectorsTests.Built`), written back as its token.
@MainActor
@Suite("Search vectors")
struct SearchVectorsTests {
    static var folder: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "shared/test-vectors/search")
    }

    static let regenerate = """
    is out of date with search. Bring shared/test-vectors/search up to date: \
    TEST_RUNNER_SEARCH_VECTORS_WRITE=1 ./tests/run_tests.sh (or run SearchVectorsTests in Xcode with \
    SEARCH_VECTORS_WRITE=1 in the scheme's environment), review the diff, run scripts/privacy-check.sh \
    on it and commit it, then run the Android tests (./gradlew :core:test :store:test in android/), which read the same files.
    """

    typealias Vectors = ValueVectorsTests.Vectors
    typealias Built = TextVectorsTests.Built

    @Test("shared/test-vectors/search is up to date with search")
    func vectorsAreUpToDate() throws {
        let files = try Self.all()
        let writes = ProcessInfo.processInfo.environment["SEARCH_VECTORS_WRITE"] == "1"
        let manager = FileManager.default
        if writes { try manager.createDirectory(at: Self.folder, withIntermediateDirectories: true) }
        for file in files {
            let url = Self.folder.appending(path: "\(file.name).json")
            let fresh = try Self.render(file)
            if writes {
                try fresh.write(to: url, atomically: true, encoding: .utf8)
                continue
            }
            let committed = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            #expect(committed == fresh, Comment(rawValue: "\(file.name).json " + Self.regenerate))
        }
        let names = Set(files.map { "\($0.name).json" })
        let present = (try? manager.contentsOfDirectory(atPath: Self.folder.path(percentEncoded: false))) ?? []
        for stale in present where stale.hasSuffix(".json") && !names.contains(stale) {
            if writes {
                try manager.removeItem(at: Self.folder.appending(path: stale))
            } else {
                Issue.record(Comment(rawValue: "\(stale) is written by no rule any more " + Self.regenerate))
            }
        }
    }

    static func all() throws -> [Vectors] {
        try [matching(), redacting(), outside(), remembering(), records()]
    }

    /// The file, with every number built when the test ran written back as its token.
    static func render(_ file: Vectors) throws -> String {
        let document: JSONValue = .object([
            "rule": .string(file.rule),
            "source": .string(file.source),
            "shape": .string(file.shape),
            "writtenBy": "ios/DosarCuSinaTests/SearchVectorsTests.swift",
            "built": .string(Built.explanation),
            "cases": .array(file.cases),
        ])
        let text = String(decoding: try MachineText.jsonEncoder(.readable).encode(document), as: UTF8.self) + "\n"
        return Built.written(text, for: tokens)
    }

    static func optional(_ text: String?) -> JSONValue { text.map(JSONValue.string) ?? .null }

    static let moments: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    /// The calendar and the moment the household is worked out in, whatever the machine says: days
    /// counted in Bucharest (the zone `noon` makes its moments in), so a runner in UTC writes the same file.
    static let calendar = Calendar.dosar(in: TimeZone(identifier: "Europe/Bucharest") ?? .gmt)
    static let now = noon("2026-11-26", calendar: calendar)

    static func moment(_ date: Date?) -> JSONValue { date.map { .string(moments.string(from: $0)) } ?? .null }

    // MARK: Numbers built when the test runs

    /// A microchip's 15 digits that pass the card check (a Maestro card's shape), alone and grouped.
    static let chipToken = "{luhn:64200000000123}"
    static let tokens = [chipToken]
    static var chip: String { Built.expand(chipToken) }

    // MARK: Matching and ranking

    static func document(_ id: String, _ kind: SearchResultKind = .document, title: String, subtitle: String? = nil,
                         fields: [(String, Int)], date: String? = nil, sensitive: Bool = false) -> SearchDocument {
        SearchDocument(id: id, kind: kind, title: title, subtitle: subtitle, route: .home,
                       fields: fields.map { SearchField($0.0, weight: $0.1) },
                       date: date.flatMap(MachineText.moment), isSensitive: sensitive)
    }

    static func json(_ document: SearchDocument) -> JSONValue {
        .object([
            "id": .string(document.id),
            "kind": .string(document.kind.rawValue),
            "title": .string(document.title),
            "subtitle": optional(document.subtitle),
            "fields": .array(document.fields.map { .object(["text": .string($0.text), "weight": .int($0.weight)]) }),
            "date": moment(document.date),
            "isSensitive": .bool(document.isSensitive),
        ])
    }

    typealias Query = (text: String, kinds: [SearchResultKind]?, limit: Int?)

    static func matching() -> Vectors {
        let title = SearchField.Weight.title, identifier = SearchField.Weight.identifier, label = SearchField.Weight.label
        let value = SearchField.Weight.value, note = SearchField.Weight.note, extracted = SearchField.Weight.extracted
        let groups: [(name: String, documents: [SearchDocument], queries: [Query])] = [
            ("diacritics, case and every word", [
                document("a", title: "Poliță RCA 2026", fields: [("Poliță RCA 2026", title), ("Daune: 021 000 0000", extracted)]),
                document("b", .provider, title: "Ștefan Instalații", fields: [("Ștefan Instalații", title), ("Instalator", label)]),
                document("c", .historyEntry, title: "Revizie", fields: [("Revizie", title), ("polița veche e în torpedou", note)]),
            ], [
                ("polita", nil, nil), ("POLIȚA", nil, nil), ("STEFAN", nil, nil), ("instalator", nil, nil), ("instal", nil, nil),
                ("polita rca", nil, nil), ("pol daune", nil, nil), ("polita lipsa", nil, nil), ("   ", nil, nil), ("", nil, nil),
                ("torpedou", nil, nil), ("polita", [.historyEntry], nil), ("polita", [.provider], nil), ("polita", nil, 1),
                ("021", nil, nil), ("rca, 2026!", nil, nil),
            ]),
            ("cedilla and comma below", [
                document("s", title: "Şcoala de şoferi", fields: [("Şcoala de şoferi", title), ("Ţara Bârsei, Mâine îţi scriu", note)]),
                document("t", title: "Școala de șoferi", fields: [("Școala de șoferi", title), ("Țara Bârsei", note)]),
            ], [
                ("școala", nil, nil), ("şcoala", nil, nil), ("scoala soferi", nil, nil), ("țara", nil, nil), ("ţara", nil, nil),
                ("barsei", nil, nil), ("mâine îți", nil, nil), ("ITI", nil, nil),
            ]),
            ("never the middle of a word", [
                document("n", title: "Factură neachitată", fields: [("Factură neachitată", title), ("Nota bene: rcaexemplu", note)]),
                document("p", title: "Factură achitată", fields: [("Factură achitată", title)]),
            ], [
                ("achitat", nil, nil), ("achit", nil, nil), ("neach", nil, nil), ("chitata", nil, nil), ("rca", nil, nil),
                ("exemplu", nil, nil), ("factura achitata", nil, nil), ("achitata factura", nil, nil),
            ]),
            ("codes compared without separators", [
                document("car", .asset, title: "VW Golf", subtitle: "Volkswagen Golf", fields: [
                    ("VW Golf", title), ("Mașini", label), ("Număr B-123-ABC", identifier), ("b123abc", identifier),
                    ("IBAN RO49 AAAA 1B31 0075 9384 0000", value), ("RO49AAAA1B31007593840000", value),
                ]),
            ], [
                ("B-123-ABC", nil, nil), ("b123abc", nil, nil), ("B 123 ABC", nil, nil), ("b12", nil, nil), ("123", nil, nil),
                ("ro49aaaa", nil, nil), ("RO49 AAAA", nil, nil), ("1b31", nil, nil), ("masini", nil, nil),
            ]),
            ("the preview line adds something", [
                document("d", .obligation, title: "RCA", subtitle: "VW Golf · 3 martie", fields: [
                    ("RCA", title), ("VW Golf", label), ("Golful din garaj", note),
                ]),
                document("e", .component, title: "Plăcuțe frână față", subtitle: "VW Golf · 3 martie", fields: [
                    ("Plăcuțe frână față", title), ("Frâne placute", label), ("VW Golf", label),
                ]),
                document("f", .provider, title: "Service Exemplu", subtitle: "Mecanic", fields: [
                    ("Service Exemplu", title), ("Mecanic", label), ("0722 123 456", identifier), ("", value), ("Mecanic de încredere", note),
                ]),
            ], [
                ("golf", nil, nil), ("rca", nil, nil), ("garaj", nil, nil), ("placute", nil, nil), ("frana", nil, nil),
                ("mecanic", nil, nil), ("martie", nil, nil), ("0722", nil, nil), ("incredere", nil, nil),
            ]),
            ("ranking and ties", [
                document("x10", title: "Factura 10", fields: [("Factura 10", title)]),
                document("x2", title: "Factura 2", fields: [("Factura 2", title)]),
                document("x1b", title: "factura 1b", fields: [("factura 1b", title)]),
                document("xa", title: "Factura alfa", fields: [("Factura alfa", title)]),
                document("xB", title: "Factura Beta", fields: [("Factura Beta", title)]),
                document("new", title: "Factura veche", fields: [("Factura veche", title)], date: "2026-05-01T10:00:00Z"),
                document("old", title: "Factura nouă", fields: [("Factura nouă", title)], date: "2025-05-01T10:00:00Z"),
                document("prefix", title: "Facturare lunară", fields: [("Facturare lunară", title)]),
                document("noted", title: "Dosar", fields: [("Dosar", title), ("factura de gaz", note)]),
                document("twice", title: "Factura și factura", fields: [("Factura", title), ("factura", value), ("facturi", note)]),
            ], [
                ("factura", nil, nil), ("factur", nil, nil), ("factura", nil, 3), ("factura gaz", nil, nil), ("factura 2", nil, nil),
                ("dosar factura", nil, nil),
            ]),
        ]
        let cases: [JSONValue] = groups.map { group in
            let index = SearchIndex(group.documents)
            let queries: [JSONValue] = group.queries.map { query in
                let results = index.search(query.text, limit: query.limit ?? 50, kinds: query.kinds.map(Set.init))
                return .object([
                    "query": .string(query.text),
                    "kinds": query.kinds.map { .array($0.map { .string($0.rawValue) }) } ?? .null,
                    "limit": query.limit.map(JSONValue.int) ?? .null,
                    "tokens": .array(SearchText.tokens(query.text).map(JSONValue.string)),
                    "results": .array(results.map { result in
                        .object(["id": .string(result.id), "score": .int(result.score), "snippet": optional(result.snippet)])
                    }),
                ])
            }
            return .object([
                "name": .string(group.name),
                "documents": .array(group.documents.map(json)),
                "queries": .array(queries),
            ])
        }
        return Vectors(
            name: "search-matching",
            rule: "SearchIndex.search(_:limit:kinds:) and SearchText.tokens(_:): every query word the start of a folded word, scored by the field's weight, ranked by score, then newer, then title",
            source: "ios/DosarCuSina/Services/Search/SearchEngine.swift",
            shape: "name: what the group bites on. documents: the index's documents (subtitle as the row shows it, date a moment or null). queries: each query with the kinds and limit it is asked with (null for none), its tokens, and the results in order: id, score and the preview line (null for none).",
            cases: cases
        )
    }

    // MARK: What search keeps

    static func kept(_ values: [(String, FieldType)]) -> PaymentCardNumbers.KeptWhole {
        PaymentCardNumbers.KeptWhole(typed: values.map { (text: Built.expand($0.0), type: $0.1) })
    }

    static func keptJSON(_ values: [(String, FieldType)]) -> JSONValue {
        .array(values.map { .object(["text": .string($0.0), "type": .string($0.1.rawValue)]) })
    }

    static func redacting() -> Vectors {
        let sealed = SecretSealer.prefix + "AAAA"
        let chipField: [(String, FieldType)] = [(chipToken, .microchip)]
        let inputs: [(text: String, kept: [(String, FieldType)])] = [
            ("CNP 1800101990006", []), ("1800101990006", []), ("CNP:1800101990006, nascut", []), ("18001019900061", []),
            ("180010199000", []), ("Tel 1800101990006 și 1800101990006", []), ("x1800101990006y", []),
            ("Plătit cu 4111 1111 1111 1111 la service", []), ("Card 5555-5555-5555-4444", []), ("card •••• 1111", []),
            ("•••• •••• •••• 4444 și restul", []), ("Microcip \(chipToken) citit", chipField), ("Microcip \(chipToken) citit", []),
            ("Cip \(chipToken), card 4111 1111 1111 1111", chipField), ("IBAN RO49 AAAA 1B31 0075 9384 0000", []),
            ("RO49AAAA1B31007593840000", []), ("Cod \(sealed) de alarmă", []), (sealed, []), ("Coduri \(sealed)  \(sealed)x", []),
            ("Telefon 0722 123 456", []), ("VW Golf 2018", []), ("", []), ("fără cifre", []), ("Șofer: Ștefan Țăran", []),
            ("Suma 1 250 lei, CNP 1800101990006, card 4111111111111111", []),
        ]
        let cases: [JSONValue] = inputs.map { input in
            let text = Built.expand(input.text)
            return .object([
                "text": .string(input.text),
                "kept": keptJSON(input.kept),
                "redacted": .string(SearchPrivacy.redacting(text, keeping: kept(input.kept))),
                "mayRemember": .bool(SearchPrivacy.mayRemember(text)),
            ])
        }
        return Vectors(
            name: "search-redacting",
            rule: "SearchPrivacy.redacting(_:keeping:) and mayRemember(_:): what the index and the recent searches never keep (a CNP-shaped number, a card number, masked or not, a sealed value), a section's own typed values kept whole",
            source: "ios/DosarCuSina/Services/Search/SearchPrivacy.swift",
            shape: "text: a text (with built tokens). kept: the section's typed values kept whole (text, field type). redacted: what search keeps of it. mayRemember: whether it may be remembered as typed (nothing kept whole).",
            cases: cases
        )
    }

    static func outside() -> Vectors {
        let sealed = SecretSealer.prefix + "AAAA"
        let inputs: [(text: String?, withheld: [String], kept: [(String, FieldType)])] = [
            ("Pașaport – RX 123456", ["RX 123456"], []), ("Pașaport RX-123456", ["rx123456"], []), ("Pașaport rx123456", ["RX 123456"], []),
            ("RX 123456", ["RX 123456"], []), ("Buletin AB 1234", ["AB12"], []), ("Carte de identitate · 1800101990006", [], []),
            ("Card 4111 1111 1111 1111", [], []), ("Rex · \(chipToken)", [], [(chipToken, .microchip)]), ("Rex · \(chipToken)", [], []),
            ("Cod \(sealed)", [], []), ("  VW   Golf  ", [], []), ("— : ·", [], []), (nil, [], []), ("", [], []),
            ("Asigurare POL-000000", ["POL-000000", "POL 000000"], []), ("Ștefan Țăran", ["ȘTEFAN"], []),
            ("Contract #12345678", ["12345678"], []), ("Cod ABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDE", ["ABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDE"], []),
        ]
        let cases: [JSONValue] = inputs.map { input in
            .object([
                "text": optional(input.text),
                "withheld": .array(input.withheld.map(JSONValue.string)),
                "kept": keptJSON(input.kept),
                "outside": optional(SearchPrivacy.outsideText(input.text.map(Built.expand), withholding: input.withheld, keeping: kept(input.kept))),
            ])
        }
        let shows: [JSONValue] = [(false, false), (true, false), (false, true), (true, true)].map { locked, example in
            .object([
                "isLocked": .bool(locked), "isExample": .bool(example),
                "mayShowOutside": .bool(SearchPrivacy.mayShowOutside(isLocked: locked, isExample: example)),
            ])
        }
        let lists: [JSONValue] = [false, true].map {
            .object(["appLockEnabled": .bool($0), "outsideListsAnything": .bool(SearchPrivacy.outsideListsAnything(appLockEnabled: $0))])
        }
        return Vectors(
            name: "search-outside",
            rule: "SearchPrivacy.outsideText(_:withholding:keeping:), mayShowOutside(isLocked:isExample:) and outsideListsAnything(appLockEnabled:): what may be shown of the binder outside the app",
            source: "ios/DosarCuSina/Services/Search/SearchPrivacy.swift",
            shape: "Each case is one of three: text (null for none), withheld (values the category keeps out of search) and kept (typed values kept whole) give outside, the text as it may be shown outside, or null; isLocked and isExample give mayShowOutside; appLockEnabled gives outsideListsAnything.",
            cases: cases + shows + lists
        )
    }

    static func remembering() -> Vectors {
        let open = SearchResult(document: document("o", title: "Golf", fields: []), score: 1)
        let locked = SearchResult(document: document("l", title: "Cazier", fields: [], sensitive: true), score: 1)
        let found: [(query: String, results: [SearchResult])] = [
            ("golf", []), ("golf", [open]), ("cazier", [locked]), ("cazier", [open, locked]), ("4111 1111 1111 1111", [open]),
            ("cnp 1800101990006", []), ("B-123-ABC", [open]),
        ]
        let cases: [JSONValue] = found.map { item in
            .object([
                "query": .string(item.query),
                "foundLocked": .array(item.results.map { .bool($0.document.isSensitive) }),
                "mayRemember": .bool(SearchPrivacy.mayRemember(item.query, results: item.results)),
            ])
        }
        let lists: [(query: String, items: [String], limit: Int)] = [
            ("golf", [], 8), ("Golf", ["golf", "rca"], 8), ("  rca  ", ["golf", "RCA"], 8), ("poliță", ["polita", "golf"], 8),
            ("", ["golf"], 8), ("   ", ["golf"], 8), ("nou", ["a", "b", "c"], 3), ("Şcoala", ["școala", "x"], 8),
        ]
        let adding: [JSONValue] = lists.map { item in
            .object([
                "adding": .string(item.query),
                "to": .array(item.items.map(JSONValue.string)),
                "limit": .int(item.limit),
                "recent": .array(RecentSearches.adding(item.query, to: item.items, limit: item.limit).map(JSONValue.string)),
            ])
        }
        return Vectors(
            name: "search-remember",
            rule: "SearchPrivacy.mayRemember(_:results:) and RecentSearches.adding(_:to:limit:): a search kept among the recent ones only when its words may be remembered and it found nothing locked; the same search in another case or without diacritics moves to the top",
            source: "ios/DosarCuSina/Services/Search/SearchPrivacy.swift, ios/DosarCuSina/Views/Search/SearchSupport.swift",
            shape: "Each case is one of two: query with foundLocked (for each result, whether it is in a locked section) gives mayRemember; adding, to and limit give recent, the list after adding.",
            cases: cases + adding
        )
    }

    // MARK: What each record gives the index

    /// A household that bites: a plate, a VIN and an IBAN; a CNP and a document number kept out; a
    /// PIN and a secret row; a card number in a note; a microchip kept whole as the section's own;
    /// a locked category and a section whose category hasn't arrived; parts done twice; a firm with
    /// two trades; documents filed through a deadline, a visit and a part, archived, read off an
    /// identity document, and one of the whole household's.
    static func records() throws -> Vectors {
        let container = try makeInMemoryContainer()
        let context = PersistenceController.context(in: container)
        // Letters in every group, so no run of an id's digits reads as a card number to the privacy check.
        func id(_ n: Int) -> UUID { UUID(uuidString: "5E000000-AB00-4C00-8D00-E0000000\(1000 + n)")! }
        let sealed = SecretSealer.prefix + "AAAA"

        let car = TemplateDefinition(
            key: "search.car", name: "Mașini", symbol: "car", tint: .blue,
            sections: [FieldSection(key: "main", title: "Date", fields: [
                FieldDefinition(key: "car.plate", label: "Număr", type: .plate, role: .identifier),
                FieldDefinition(key: "car.vin", label: "Serie șasiu", type: .vin, role: .keyFact),
                FieldDefinition(key: "car.make", label: "Marcă", type: .text, role: .subtitle),
                FieldDefinition(key: "car.model", label: "Model", type: .text, role: .subtitle),
                FieldDefinition(key: "car.iban", label: "Cont", type: .iban),
                FieldDefinition(key: "car.ownerCNP", label: "CNP proprietar", type: .text, isSensitive: true),
                FieldDefinition(key: "car.pin", label: "PIN", type: .secret),
                FieldDefinition(key: "car.km", label: "Kilometraj", type: .number),
                FieldDefinition(key: "car.color", label: "Culoare", type: .text),
            ])],
            components: [ComponentDefinition(key: "brakes.front", name: "Plăcuțe frână față", group: "Frâne", synonyms: ["placute", "frana fata"])],
            behavior: CategoryBehavior(visit: .none, singular: nil)
        )
        let pets = TemplateDefinition(
            key: "search.pet", name: "Animale", symbol: "pawprint", tint: .orange,
            sections: [FieldSection(key: "main", title: "Date", fields: [
                FieldDefinition(key: "pet.chip", label: "Microcip", type: .microchip, role: .keyFact),
                FieldDefinition(key: "pet.breed", label: "Rasă", type: .choice, role: .subtitle,
                                options: [ChoiceOption(key: "breed.tabby", label: "Europeană tărcată")]),
                FieldDefinition(key: "pet.vet", label: "Medic", type: .text, role: .issuer),
            ])],
            behavior: CategoryBehavior(visit: .none, singular: nil)
        )
        let papers = TemplateDefinition(
            key: "search.papers", name: "Acte", symbol: "doc", tint: .gray,
            sections: [FieldSection(key: "main", title: "Date", fields: [
                FieldDefinition(key: "paper.number", label: "Număr", type: .text, role: .documentNumber, isSensitive: true),
                FieldDefinition(key: "paper.holder", label: "Titular", type: .text, role: .holder),
            ])],
            behavior: CategoryBehavior(visit: .none, singular: nil)
        )
        let templates = [car, pets, papers].enumerated().map { CategoryTemplate(definition: $1, isBuiltIn: false, homeOrder: $0) }
        templates.forEach(context.insert)
        try templates[2].setLock(true, now: now)

        let golf = Asset(id: id(1), name: "VW Golf", templateKey: car.key, values: FieldValues([
            "car.plate": .text("b 123 abc"), "car.vin": .text("WVWZZZ1KZAW000000"), "car.make": .text("Volkswagen"),
            "car.model": .text("Golf"), "car.iban": .text("RO49AAAA1B31007593840000"), "car.ownerCNP": .text("1800101990006"),
            "car.pin": .text(sealed), "car.km": .number(125000), "car.color": .text("gri, card 4111 1111 1111 1111"),
        ]), notes: "Plătit cu 4111 1111 1111 1111 la service; CNP 1800101990006 pe talon")
        golf.customFacts = [
            CustomFact(id: id(901), label: "Cod alarmă", value: sealed, isSecret: true),
            CustomFact(id: id(902), label: "Parcare", value: "Locul 12, nivelul -1"),
            CustomFact(id: id(903), label: "Notă privată", value: "ascuns", isSensitive: true),
        ]
        let rex = Asset(id: id(2), name: "Rex", templateKey: pets.key, values: FieldValues([
            "pet.chip": .text(chip), "pet.breed": .text("breed.tabby"), "pet.vet": .text("Cabinet Veterinar Exemplu"),
        ]), notes: "Microcip \(chip) citit la vaccin")
        let passport = Asset(id: id(3), name: "Pașaport Ana", templateKey: papers.key, values: FieldValues([
            "paper.number": .text("RX 123456"), "paper.holder": .text("Ana Exemplu"),
        ]), notes: "Ține-l în sertar")
        let stray = Asset(id: id(4), name: "Secțiune fără categorie", templateKey: "search.absent", notes: "sosește mai târziu")
        for (offset, section) in [golf, rex, passport, stray].enumerated() {
            context.insert(section)
            section.createdAt = noon("2026-01-0\(offset + 1)")
            section.updatedAt = noon("2026-02-0\(offset + 1)")
        }

        let service = Provider(id: id(11), name: "Service Exemplu S.R.L.", trades: [.mechanic, .tyreShop], phone: "0722 123 456")
        let parts = Provider(id: id(12), name: "Piese Exemplu", trades: [])
        let plumber = Provider(id: id(13), name: "Ștefan Instalații", trades: [.plumber], phone: "0700 000 000")
        for (offset, provider) in [service, parts, plumber].enumerated() {
            context.insert(provider)
            provider.createdAt = noon("2026-01-1\(offset)")
            provider.updatedAt = noon("2026-02-1\(offset)")
        }
        service.address = "Str. Exemplu 1, București"
        service.notes = "Întreabă de Ștefan"
        service.assets = [golf]

        func deadline(_ n: Int, _ title: String, _ kind: ObligationKind, _ due: String, in section: Asset?) -> Obligation {
            let obligation = Obligation(id: id(n), title: title, kind: kind, dueDay: CalendarDay(due))
            context.insert(obligation)
            obligation.asset = section
            return obligation
        }
        let rca = deadline(21, "RCA", .legal, "2027-01-10", in: golf)
        rca.reference = "POL-000000"
        rca.provider = "Asigurări Exemplu S.A."
        rca.notes = "Golful din garaj"
        let vignette = deadline(22, "Rovinietă VW Golf", .legal, "2026-12-01", in: golf)
        let renewal = deadline(23, "Reînnoire pașaport", .legal, "2028-05-05", in: passport)
        renewal.notes = "la ghișeu, cu 1800101990006"
        let tax = deadline(24, "Impozit locuință", .legal, "2027-03-31", in: nil)
        tax.notes = "Card 5555 5555 5555 4444"
        let strayDeadline = deadline(25, "Termen fără categorie", .routine, "2027-02-02", in: stray)

        func record(_ n: Int, _ kind: HistoryKind, _ title: String, _ day: String, in section: Asset) -> HistoryEntry {
            let entry = HistoryEntry(id: id(n), kind: kind, title: title, occurredAt: noon(day))
            context.insert(entry)
            entry.asset = section
            return entry
        }
        let pads = record(31, .repair, "Schimb plăcuțe", "2026-03-03", in: golf)
        pads.note = "Plătit cu 5555 5555 5555 4444"
        pads.reference = "F-123"
        pads.providers = [service]
        let revision = record(32, .maintenance, "Revizie", "2025-10-10", in: golf)
        let vaccine = record(33, .visit, "Vaccin anual", "2026-04-04", in: rex)
        vaccine.note = "Cip \(chip) verificat"
        let counter = record(34, .visit, "Programare ghișeu", "2026-05-05", in: passport)
        counter.note = "Adus actele"
        // One part per record and one firm per list, so every list reads in one order.
        let wiping = record(35, .repair, "Schimb ștergătoare", "2026-02-20", in: golf)
        let oilChange = record(36, .maintenance, "Schimb ulei", "2025-06-06", in: golf)

        @discardableResult
        func part(_ n: Int, _ name: String, key: String?, brand: String? = nil, supplier: Provider? = nil, of entry: HistoryEntry) -> ServiceItem {
            let item = ServiceItem(id: id(n), name: name, componentKey: key)
            context.insert(item)
            item.partBrandOrCode = brand
            item.supplier = supplier
            item.entry = entry
            return item
        }
        let newPads = part(41, "Placute frana fata", key: "brakes.front", brand: "Bosch 0 986", supplier: parts, of: pads)
        part(42, "Ștergătoare", key: "custom.stergatoare", of: wiping)
        part(43, "Plăcuțe față", key: "brakes.front", brand: "ATE", of: revision)
        part(44, "Ulei motor", key: nil, of: oilChange)

        @discardableResult
        func paper(_ n: Int, title: String?, file: String, kind: DocumentKind = .other, text: String? = nil, day: String? = nil) -> DosarCuSina.Attachment {
            let attachment = DosarCuSina.Attachment(id: id(n), fileName: file, contentType: "com.adobe.pdf", data: nil, kind: kind)
            attachment.title = title
            attachment.extractedText = text
            attachment.documentDay = day.map { CalendarDay($0) }
            attachment.createdAt = noon("2026-06-0\(n % 10)")
            context.insert(attachment)
            return attachment
        }
        paper(51, title: "Poliță RCA 2026", file: "polita.pdf", kind: .policy, text: "Daune 021 000 0000, plătit cu 4111111111111111", day: "2026-01-10").asset = golf
        let old = paper(52, title: nil, file: "polita-veche.pdf", kind: .policy, text: "Poliță RCA 2025 POL-000000")
        old.isArchived = true
        old.obligation = rca
        paper(53, title: "Factură plăcuțe", file: "factura.pdf", kind: .invoice, text: "Total 450 lei, card 4111 1111 1111 1111").serviceItem = newPads
        paper(54, title: "Bon revizie", file: "bon.jpg", kind: .receipt, text: "Revizie la 120.000 km").historyEntry = revision
        paper(55, title: "Carnet de sănătate", file: "carnet.pdf", text: "Microcip \(chip), card 5555555555554444", day: "2026-04-04").asset = rex
        paper(56, title: "Pașaport", file: "pasaport.jpg", kind: .identity, text: "P<ROUEXEMPLU<<ANA 1800101990006").asset = passport
        paper(57, title: "Copie buletin", file: "buletin.jpg", kind: .identity, text: "CNP 1800101990006 IDROU").asset = golf
        paper(58, title: "Contract chirie", file: "chirie.pdf", kind: .contract, text: "Chiria se plătește lunar").obligation = tax
        paper(59, title: nil, file: "scan.pdf", text: "Pagina 1")

        let builder = SearchIndexBuilder(context: context, calendar: calendar)
        let documents = try builder.buildByRecord().values.flatMap { $0 }.sorted { $0.id < $1.id }
        var days: Set<CalendarDay> = []
        for obligation in [rca, vignette, renewal, tax, strayDeadline] { days.insert(obligation.dueDay) }
        for entry in [pads, revision, vaccine, counter, wiping, oilChange] { days.insert(CalendarDay(entry.occurredAt, calendar: calendar)) }
        let household = try Self.household(context: context, templates: templates)
        let expected: [JSONValue] = documents.map { document in
            var object = Self.json(document)
            if case .object(var fields) = object {
                fields["route"] = Self.route(document.route)
                object = .object(fields)
            }
            return object
        }
        let words: JSONValue = .object([
            "zone": .string(calendar.timeZone.identifier),
            "days": .object(Dictionary(days.map { ($0.isoString, JSONValue.string(DosarFormat.day($0, locale: .dosarDefault))) }, uniquingKeysWith: { first, _ in first })),
            "trades": .object(Dictionary(ProviderTrade.allCases.map { ($0.rawValue, JSONValue.string($0.title)) }, uniquingKeysWith: { first, _ in first })),
            "archived": .string(String(localized: "arhivat")),
        ])
        return Vectors(
            name: "search-records",
            rule: "SearchIndexBuilder.buildByRecord(): what each record of a binder gives the index, secrets and what a category keeps out of search left out, CNP-shaped numbers, card numbers and sealed values taken out, a section's own typed values kept whole",
            source: "ios/DosarCuSina/Services/Search/SearchIndexBuilder.swift",
            shape: "One case: household (its categories with their fields and components, and whether each is locked here; its sections with each value as stored and as shown; deadlines, records of history with their parts, firms and documents, linked by id), words (the time zone days were counted in, each day and trade as the rows say it, and the word for an archived document) and documents: every document the index holds, by id, with its route.",
            cases: [.object(["household": household, "words": words, "documents": .array(expected)])]
        )
    }

    static func route(_ route: AppRoute) -> JSONValue {
        switch route {
        case .asset(let id): .object(["kind": "asset", "id": .string(id.uuidString)])
        case .obligation(let id): .object(["kind": "obligation", "id": .string(id.uuidString)])
        case .historyEntry(let id): .object(["kind": "historyEntry", "id": .string(id.uuidString)])
        case .provider(let id): .object(["kind": "provider", "id": .string(id.uuidString)])
        case .document(let id): .object(["kind": "document", "id": .string(id.uuidString)])
        default: .object(["kind": "other"])
        }
    }

    static func uuid(_ id: UUID?) -> JSONValue { id.map { .string($0.uuidString) } ?? .null }

    /// The household as stored, read back from the context.
    static func household(context: ModelContext, templates: [CategoryTemplate]) throws -> JSONValue {
        let templateRows: [JSONValue] = templates.map { template in
            let definition = template.definition
            return .object([
                "key": .string(template.key),
                "name": .string(template.name),
                "isLocked": .bool(template.isSensitive),
                "fields": .array(definition.allFields.map { field in
                    .object([
                        "key": .string(field.key), "label": .string(field.label), "type": .string(field.type.rawValue),
                        "role": optional(field.role?.rawValue), "isSensitive": .bool(field.isSensitive),
                        "options": .array((field.options ?? []).map { .object(["key": .string($0.key), "label": .string($0.label)]) }),
                    ])
                }),
                "components": .array(definition.components.map { component in
                    .object([
                        "key": .string(component.key), "name": .string(component.name), "group": .string(component.group),
                        "synonyms": .array(component.synonyms.map(JSONValue.string)),
                    ])
                }),
            ])
        }
        let byKey = Dictionary(templates.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let assets = try context.fetch(FetchDescriptor<Asset>()).sorted { $0.id.uuidString < $1.id.uuidString }
        let assetRows: [JSONValue] = assets.map { asset in
            let fields = byKey[asset.templateKey]?.definition.allFields ?? []
            let values: [String: JSONValue] = Dictionary(asset.values.storage.map { key, value in
                let field = fields.first { $0.key == key }
                return (key, JSONValue.object([
                    "value": (try? JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))) ?? .null,
                    "shown": field.map { .string(FieldFormatter.display(value, field: $0, locale: .dosarDefault)) } ?? .null,
                ]))
            }, uniquingKeysWith: { first, _ in first })
            return .object([
                "id": .string(asset.id.uuidString), "name": .string(asset.name), "templateKey": .string(asset.templateKey),
                "notes": optional(asset.notes), "updatedAt": moment(asset.updatedAt), "values": .object(values),
                "facts": .array(asset.customFacts.map { fact in
                    .object([
                        "id": .string(fact.id.uuidString), "label": .string(fact.label), "value": .string(fact.value),
                        "isSensitive": .bool(fact.isSensitive), "isSecret": .bool(fact.isSecret),
                    ])
                }),
            ])
        }
        let obligations = try context.fetch(FetchDescriptor<Obligation>()).sorted { $0.id.uuidString < $1.id.uuidString }
        let obligationRows: [JSONValue] = obligations.map { obligation in
            .object([
                "id": .string(obligation.id.uuidString), "title": .string(obligation.title), "dueDay": .string(obligation.dueDay.isoString),
                "reference": optional(obligation.reference), "provider": optional(obligation.provider), "notes": optional(obligation.notes),
                "assetId": uuid(obligation.asset?.id),
            ])
        }
        let entries = try context.fetch(FetchDescriptor<HistoryEntry>()).sorted { $0.id.uuidString < $1.id.uuidString }
        let entryRows: [JSONValue] = entries.map { entry in
            .object([
                "id": .string(entry.id.uuidString), "kind": .string(entry.kindRaw), "title": .string(entry.title),
                "occurredAt": moment(entry.occurredAt), "note": optional(entry.note), "reference": optional(entry.reference),
                "assetId": uuid(entry.asset?.id), "providerIds": .array((entry.providers ?? []).map { .string($0.id.uuidString) }),
                "items": .array((entry.items ?? []).sorted { $0.id.uuidString < $1.id.uuidString }.map { item in
                    .object([
                        "id": .string(item.id.uuidString), "name": .string(item.name), "componentKey": optional(item.componentKey),
                        "partBrandOrCode": optional(item.partBrandOrCode), "supplierId": uuid(item.supplier?.id),
                    ])
                }),
            ])
        }
        let providers = try context.fetch(FetchDescriptor<Provider>()).sorted { $0.id.uuidString < $1.id.uuidString }
        let providerRows: [JSONValue] = providers.map { provider in
            .object([
                "id": .string(provider.id.uuidString), "name": .string(provider.name), "trades": .array(provider.trades.map(JSONValue.string)),
                "phone": optional(provider.phone), "address": optional(provider.address), "notes": optional(provider.notes),
                "updatedAt": moment(provider.updatedAt), "assetIds": .array((provider.assets ?? []).map { .string($0.id.uuidString) }),
            ])
        }
        let attachments = try context.fetch(FetchDescriptor<DosarCuSina.Attachment>()).sorted { $0.id.uuidString < $1.id.uuidString }
        let attachmentRows: [JSONValue] = attachments.map(paperRow)
        return .object([
            "templates": .array(templateRows), "assets": .array(assetRows), "obligations": .array(obligationRows),
            "historyEntries": .array(entryRows), "providers": .array(providerRows), "attachments": .array(attachmentRows),
        ])
    }

    static func paperRow(_ attachment: DosarCuSina.Attachment) -> JSONValue {
        var row: [String: JSONValue] = [:]
        row["id"] = .string(attachment.id.uuidString)
        row["title"] = optional(attachment.title)
        row["fileName"] = .string(attachment.fileName)
        row["kind"] = .string(attachment.kindRaw)
        row["extractedText"] = optional(attachment.extractedText)
        row["isArchived"] = .bool(attachment.isArchived)
        row["documentDay"] = optional(attachment.documentDay?.isoString)
        row["createdAt"] = moment(attachment.createdAt)
        row["assetId"] = uuid(attachment.asset?.id)
        row["obligationId"] = uuid(attachment.obligation?.id)
        row["historyEntryId"] = uuid(attachment.historyEntry?.id)
        row["serviceItemId"] = uuid(attachment.serviceItem?.id)
        return .object(row)
    }
}
