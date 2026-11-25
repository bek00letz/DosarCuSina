import Foundation
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import DosarCuSina

/// The iOS golden archives in `shared/fixtures/golden/ios/`: `household.dosar`, its
/// password-protected twin `household-password.dosar`, and their contents unpacked in
/// `expected/` (the manifest and the data files as written, the vault's files by path and
/// SHA-256 in `vault.json`). The Android suite imports them and compares what came in with
/// `expected/`, record by record.
///
/// They are made here from a placeholder household built through the app's own actions
/// (`GoldenHousehold`), and kept fresh by contents, not bytes: the test exports again and
/// fails when what it writes differs from what is committed, leaving out only what must
/// differ from one run to the next (see `GoldenContents.canonical`). Bring them up to date
/// with `TEST_RUNNER_GOLDEN_ARCHIVES_WRITE=1` (see `regenerate`), then review the diff of
/// `expected/` and commit it with both archives.
@MainActor
@Suite("Golden archives", .serialized)
struct GoldenArchiveTests {
    /// `shared/fixtures/golden/`.
    static var root: URL { Fixtures.root.appending(path: "golden") }
    static var ios: URL { root.appending(path: "ios") }
    static var expected: URL { ios.appending(path: "expected") }

    /// The placeholder password of `household-password.dosar`, also written in its README.
    static let password = "parola-de-test-dosar"
    /// When the archives say they were written: a fixed moment, so the manifest and every
    /// entry's date are the same each run.
    static let exportedAt = Date(timeIntervalSince1970: 1_795_168_800) // 2026-11-20T10:00:00Z

    static let regenerate = """
    shared/fixtures/golden/ios/ is out of date with what the iOS writer makes. Bring it up to date: \
    TEST_RUNNER_GOLDEN_ARCHIVES_WRITE=1 xcodebuild test … -only-testing:DosarCuSinaTests/GoldenArchiveTests \
    (or run GoldenArchiveTests in Xcode with GOLDEN_ARCHIVES_WRITE=1 in the scheme's environment), then \
    review the diff of expected/ and commit it with both archives. Android's suite imports them.
    """

    static var writes: Bool { ProcessInfo.processInfo.environment["GOLDEN_ARCHIVES_WRITE"] == "1" }

    /// The household exported, plain and with the password.
    static func freshArchives() throws -> (plain: Data, protected: Data) {
        let container = try GoldenHousehold.build()
        let service = DossierArchiveService(container: container, calendar: GoldenHousehold.calendar)
        let folder = URL.temporaryDirectory.appending(path: "golden-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let plain = try service.exportFile(to: folder.appending(path: "plain", directoryHint: .isDirectory).creatingDirectory(), exportedAt: exportedAt)
        let protected = try service.exportFile(to: folder.appending(path: "protected", directoryHint: .isDirectory).creatingDirectory(),
                                               password: password, exportedAt: exportedAt)
        return (try Data(contentsOf: plain), try Data(contentsOf: protected))
    }

    // MARK: Fresh or failing

    @Test("The committed iOS golden archives are what the writer makes today")
    func committedArchivesAreFresh() throws {
        let fresh = try Self.freshArchives()
        let unpacked = try GoldenContents.unpack(fresh.plain)
        #expect(try GoldenContents.unpack(fresh.protected, password: Self.password) == unpacked, "The twin holds the same archive")
        if Self.writes {
            try fresh.plain.write(to: Self.ios.appending(path: "household.dosar"))
            try fresh.protected.write(to: Self.ios.appending(path: "household-password.dosar"))
            try unpacked.write(to: Self.expected)
        }
        let committed = try GoldenContents.read(Self.expected)
        let freshForm = try GoldenContents.canonical(unpacked)
        let committedForm = try GoldenContents.canonical(committed)
        for path in Set(freshForm.keys).union(committedForm.keys).sorted() where freshForm[path] != committedForm[path] {
            Issue.record(Comment(rawValue: "\(path) differs from what is committed. \(Self.regenerate)"))
        }

        // The archives committed beside it are the ones `expected/` unpacks.
        let plain = try Data(contentsOf: Self.ios.appending(path: "household.dosar"))
        #expect(!ArchiveEncryption.isEncrypted(plain))
        #expect(try GoldenContents.unpack(plain) == committed, "household.dosar unpacks to expected/")
        let protected = try Data(contentsOf: Self.ios.appending(path: "household-password.dosar"))
        #expect(ArchiveEncryption.isEncrypted(protected))
        #expect(try GoldenContents.unpack(protected, password: Self.password) == committed, "household-password.dosar opens to expected/")
        let readme = try String(contentsOf: Self.ios.appending(path: "README.md"), encoding: .utf8)
        #expect(readme.contains("`\(Self.password)`"), "The README beside them says the password")
    }

    // MARK: Both ways on this side

    @Test("Both committed golden archives come back whole into an empty binder", arguments: [false, true])
    func committedArchivesComeBackWhole(protected: Bool) throws {
        let name = protected ? "household-password.dosar" : "household.dosar"
        let archive = try Data(contentsOf: Self.ios.appending(path: name))
        let committed = try GoldenContents.read(Self.expected)
        let container = try makeInMemoryContainer()
        let service = DossierArchiveService(container: container, calendar: GoldenHousehold.calendar)
        try service.importArchive(archive, password: protected ? Self.password : nil, mode: .replace)

        // Written out again, the binder says exactly what the archive said, record by record.
        let manifest = try GoldenContents.manifest(committed)
        let again = try GoldenContents.unpack(service.exportData(appVersion: manifest.appVersion, exportedAt: Self.exportedAt))
        #expect(try GoldenContents.manifest(again).counts == manifest.counts, "\(name): every record came in")
        #expect(again.vault == committed.vault, "\(name): every page, file, thumbnail and photo came in as it was")
        for path in DossierV3.Path.dataFiles {
            let before = try GoldenContents.records(committed, path)
            let after = try GoldenContents.records(again, path)
            #expect(Set(after.keys) == Set(before.keys), "\(name): \(path) has the same records")
            for (id, record) in before where after[id] != record {
                Issue.record(Comment(rawValue: "\(name): \(path) record \(id) came back different"))
            }
        }
    }

    // MARK: What the household covers

    @Test("The golden household covers every record type and the format's edges")
    func theHouseholdCoversTheEdges() throws {
        let archive = try Self.freshArchives().plain
        let unpacked = try GoldenContents.unpack(archive)
        let records = { (path: String) in try GoldenContents.objects(unpacked, path) }
        for path in DossierV3.Path.dataFiles {
            #expect(try !records(path).isEmpty, "\(path) holds at least one record")
        }
        let everything = DossierV3.Path.dataFiles.compactMap { unpacked.files[$0] }.map { String(decoding: $0, as: UTF8.self) }.joined()

        // Secrets never leave the phone; a card number never in any text.
        #expect(!everything.contains(SecretSealer.prefix), "Nothing sealed is written")
        let sections = String(decoding: unpacked.files[DossierV3.Path.assets] ?? Data(), as: UTF8.self)
        #expect(sections.contains("document.personalNumber") && !sections.contains("document.pinAuthentication"), "A PIN field's value is left out")
        #expect(!everything.contains(GoldenHousehold.secretRowLabel), "A secret row is left out")
        #expect(everything.contains(GoldenHousehold.openRowLabel), "Beside the rows that aren't secret")
        #expect(!everything.contains("4111 1111 1111 1111") && everything.contains("•••• 1111"), "A card number is masked to its last four digits")

        // A category of one's own, and a locked one.
        let templates = try records(DossierV3.Path.templates)
        #expect(templates.contains { ($0["key"] as? String)?.hasPrefix("custom.") == true && $0["isBuiltIn"] as? Bool == false })
        #expect(templates.contains { $0["key"] as? String == BuiltInTemplates.Key.health && $0["isSensitive"] as? Bool == true })
        #expect(try records(DossierV3.Path.assets).contains { $0["templateKey"] as? String == BuiltInTemplates.Key.health })

        // Pages kept as HEIC and as JPEG, named by what they are, a PDF and a document of two pages.
        let attachments = try records(DossierV3.Path.attachments)
        let pages = attachments.flatMap { $0["pagePaths"] as? [String] ?? [] }
        let thumbnails = attachments.compactMap { $0["thumbnailPath"] as? String }
        let entries = Dictionary(try DosarZipEngine.unpackArchive(archive).map { ($0.path, $0.data) }, uniquingKeysWith: { first, _ in first })
        for path in pages + thumbnails {
            let type = entries[path].flatMap(ShareInbox.type(sniffing:))
            #expect(path.hasSuffix(".jpg") ? type == .jpeg : (path.hasSuffix(".heic") && type == .heic), "\(path) is named by what it is")
        }
        #expect(pages.contains { $0.hasSuffix(".heic") } && pages.contains { $0.hasSuffix(".jpg") })
        #expect(thumbnails.contains { $0.hasSuffix(".heic") } && thumbnails.contains { $0.hasSuffix(".jpg") })
        #expect(attachments.contains { ($0["path"] as? String)?.hasSuffix(".pdf") == true })
        #expect(attachments.contains { ($0["pagePaths"] as? [String])?.count == 2 })
        #expect(attachments.contains { $0["supersededById"] != nil && $0["isArchived"] as? Bool == true }, "A replaced document")
        #expect(attachments.contains { $0["framing"] != nil })
        #expect(try records(DossierV3.Path.assets).contains { ($0["photoPath"] as? String)?.hasPrefix(DossierV3.Path.photosPrefix) == true })

        // Deadlines: the household's own, one of the person's own, snoozed, paused, a reminder time, money.
        let obligations = try records(DossierV3.Path.obligations)
        #expect(obligations.contains { $0["assetId"] == nil && $0["blueprintKey"] as? String == HouseholdRules.rentalDeclarationKey })
        #expect(obligations.contains { $0["blueprintKey"] == nil && $0["title"] as? String == GoldenHousehold.ownDeadline })
        #expect(obligations.contains { $0["snoozedUntil"] != nil })
        #expect(obligations.contains { $0["status"] as? String == "paused" })
        #expect(obligations.contains { $0["reminderMinuteOfDay"] != nil && $0["estimatedCost"] != nil })

        // History with line items, a completion, firms and readings.
        let history = try records(DossierV3.Path.history)
        #expect(history.contains { $0["cycleDueDate"] != nil && $0["nextDueDate"] != nil }, "A completion")
        #expect(history.contains { !($0["providerIds"] as? [String] ?? []).isEmpty && $0["rating"] != nil && $0["totalCost"] != nil })
        let items = try records(DossierV3.Path.serviceItems)
        #expect(items.contains { $0["entryId"] != nil && $0["supplierId"] != nil && $0["laborCost"] != nil && $0["partsCost"] != nil })
        #expect(try records(DossierV3.Path.providers).contains { $0["taxID"] != nil && !($0["assetIds"] as? [String] ?? []).isEmpty })
        let readings = try records(DossierV3.Path.measurements)
        #expect(readings.contains { $0["basis"] as? String == "estimated" } && readings.contains { $0["basis"] as? String == "read" })
        #expect(readings.contains { $0["startsCounter"] as? Bool == true }, "A new counter")
        #expect(everything.contains("\"currency\" : \"EUR\""), "Money in another currency than the leu")

        // What a newer version wrote, kept as written.
        #expect(everything.contains("\"type\" : \"geoPoint\""), "A field value of a type this version doesn't know")
        #expect(everything.contains("\"futureNote\""), "A key this version doesn't know, inside a value")
        #expect(everything.contains("\"futureColour\""), "Inside a row under Date importante")
        #expect(everything.contains("\"skipHolidays\"") && everything.contains("\"quietHours\""), "Inside a recurrence and a reminder profile")
        #expect(everything.contains("\"futureSource\""), "Inside a document's framing")
        #expect(everything.contains("\"futureBehaviour\"") && everything.contains("\"type\" : \"stars\""), "Inside a category's behaviour and fields")
    }
}

// MARK: - The household

/// The golden archives' household: placeholder data only (AGENTS.md, item 8), built through
/// the app's actions as `ScreenshotHousehold` builds its own, never written to the store
/// directly. Each step runs as the person's step at its own fixed moment, so every change
/// time is the same each run; what a newer version wrote comes in through an import of a
/// small archive from that version (`newerArchive`).
@MainActor
enum GoldenHousehold {
    static let calendar = Calendar.bucharest
    /// The first step's moment: 2026-11-20T08:00:00Z. Each step is a minute after the one before.
    static let start = Date(timeIntervalSince1970: 1_795_161_600)
    static let ownDeadline = "Schimbă bateria telecomenzii"
    static let openRowLabel = "Loc în port"
    static let secretRowLabel = "Cod alarmă"

    final class Clock {
        var now: Date
        init(_ start: Date) { now = start }
        func next() -> Date {
            now = now.addingTimeInterval(60)
            return now
        }
    }

    static func build() throws -> ModelContainer {
        let container = try makeInMemoryContainer()
        let context = PersistenceController.context(in: container)
        let clock = Clock(start)
        let store = TemplateStore(context: context)
        try store.installBuiltIns()
        let templates = try store.templatesByKey()
        func template(_ key: String) throws -> CategoryTemplate { try #require(templates[key]) }

        let now = { clock.now }
        let assets = AssetActions(context: context, calendar: calendar, now: now, sealer: .ephemeral())
        let obligations = ObligationActions(context: context, calendar: calendar, now: now)
        let history = HistoryActions(context: context, now: now)
        let providers = ProviderActions(context: context, now: now)
        let documents = AttachmentActions(context: context, calendar: calendar)
        /// One step of the person's, at its own moment.
        func step<T>(_ work: () throws -> T) throws -> T {
            try UnitOfWork.perform(in: context, now: clock.next(), work)
        }
        func day(_ offset: Int) -> CalendarDay { CalendarDay(start, calendar: calendar).adding(days: offset, calendar: calendar) }
        func daysAgo(_ days: Int) -> Date { start.addingTimeInterval(-Double(days) * 86_400) }
        func plan(_ template: CategoryTemplate, _ values: FieldValues, dues: [String: Int] = [:]) -> [PlannedObligation] {
            assets.plannedObligations(for: template, values: values).map { planned in
                var planned = planned
                if let offset = dues[planned.blueprint.key] { planned.firstDue = day(offset) }
                planned.isSelected = PlannedObligation.startsSelected(planned.blueprint, firstDue: planned.firstDue)
                    || (dues[planned.blueprint.key] != nil && planned.firstDue != nil)
                return planned
            }
        }
        func picture(_ name: String) throws -> Data { try ArchivePicturesTests.picture(name) }
        func deadline(_ asset: Asset, _ key: String) throws -> Obligation {
            try #require((asset.obligations ?? []).first { $0.blueprintKey == key })
        }

        // Health is locked on this phone: its sections travel with the lock on.
        try step { try store.setSensitive(try template(BuiltInTemplates.Key.health), true) }

        // The people, and Ana's electronic identity card: two sides, a HEIC and a JPEG, its PIN a secret.
        var citizen = FieldValues()
        citizen[MemberFields.citizenship] = .choices([Citizenship.key("RO")])
        let ana = try step { try assets.create(name: "Ana", template: try template(BuiltInTemplates.Key.member), values: citizen) }
        try step { _ = try assets.create(name: "Mihai", template: try template(BuiltInTemplates.Key.member), values: citizen) }
        let documentsTemplate = try template(BuiltInTemplates.Key.documents)
        var card = FieldValues()
        card["document.type"] = .text(DocumentType.idCard)
        card[DocumentType.variantFieldKey] = .text(DocumentType.Variant.idCardElectronic)
        card[DocumentFields.number] = .text("XX123456")
        card[DocumentFields.personalNumber] = .text("1800101990006")
        card[DocumentFields.issueDate] = .date(day(-700))
        card[DocumentFields.expiry] = .date(day(1_125))
        card["document.pinAuthentication"] = .text("0000")
        let identity = try step {
            try assets.create(name: DocumentNaming.name(document: "Carte de identitate", holder: "Ana"), template: documentsTemplate,
                              values: card, obligations: plan(documentsTemplate, card), parent: ana)
        }
        try step {
            var draft = DocumentDraft(title: "Carte de identitate", fileName: "carte-de-identitate.heic", kind: .identity, contentType: "public.heic",
                                      pageImages: [try picture("page-front.heic"), try picture("page-back.jpg")],
                                      thumbnail: try picture("thumb-front.heic"),
                                      extractedText: "Carte de identitate, exemplu. Card de test 4111 1111 1111 1111.", documentDate: day(-700))
            draft.framing = DocumentFraming(pages: [
                PageFraming(crop: [PagePoint(x: 0.05, y: 0.1), PagePoint(x: 0.95, y: 0.08), PagePoint(x: 0.96, y: 0.9), PagePoint(x: 0.04, y: 0.92)], quarterTurns: 1),
                PageFraming(prefersWholePhoto: true),
            ])
            _ = try documents.file(draft, asset: identity)
        }

        // The car: its photo, a service with line items and its invoice, a completed ITP with its report, a replaced policy.
        let vehicle = try template(BuiltInTemplates.Key.vehicle)
        var carValues = FieldValues()
        carValues[VehicleFields.plate] = .text("B-123-ABC")
        carValues[VehicleFields.make] = .text("Volkswagen")
        carValues[VehicleFields.model] = .text("Golf")
        carValues[VehicleFields.year] = .number(2018)
        carValues["vehicle.fuel"] = .text(FuelType.petrol)
        carValues[VehicleFields.usage] = .text(VehicleUse.personal)
        carValues[VehicleFields.odometer] = .number(142_500)
        let car = try step {
            try assets.create(name: "VW Golf 2018", template: vehicle, values: carValues,
                              obligations: plan(vehicle, carValues, dues: ["vehicle.vignette": 6, "vehicle.itp": 23, "vehicle.rca": 58, "vehicle.service": 112]))
        }
        try step { try assets.setPhoto(car, try picture("photo.jpg")) }
        let mechanic = try step { try #require(try providers.findOrCreate(name: "Service Auto Exemplu SRL", taxID: "RO12345678", trade: .mechanic, phone: "0700 000 001", linkedTo: car)) }
        try step { try providers.setWouldCallAgain(mechanic, true) }
        let supplier = try step { try providers.create(name: "Magazin Piese Exemplu", trades: [.other], email: "nume@exemplu.ro", address: "Str. Exemplu nr. 1, București") }
        let service = try step {
            try history.record(
                on: car, kind: .maintenance, title: "Revizie anuală", occurredAt: daysAgo(95), metricReading: 138_900,
                totalCost: Money(Decimal(string: "1150.50") ?? 0), note: "Totul în regulă.", reference: "FCT-0001",
                items: [
                    LineItemDraft(name: "Schimb ulei și filtru", componentKey: "engine.oil", partBrandOrCode: "5W-30",
                                  cost: Money(420), laborCost: Money(120), partsCost: Money(300), warrantyMonths: 6, supplier: supplier),
                    LineItemDraft(name: "Plăcuțe frână față", componentKey: "brakes.padsFront", partSerialNumber: "SN-0001", cost: Money(380)),
                    LineItemDraft(name: "Spălare motor", notes: "Din partea casei"),
                ],
                providers: [mechanic], rating: 5
            )
        }
        try step {
            _ = try documents.file(DocumentDraft(title: "Factură revizie", fileName: "factura-revizie.pdf", kind: .invoice, contentType: "com.adobe.pdf",
                                                 originalData: try picture("invoice.pdf"), documentDate: CalendarDay(daysAgo(95), calendar: calendar)),
                                   historyEntry: service, provider: mechanic)
        }
        let itp = try deadline(car, "vehicle.itp")
        let inspection = try step { try obligations.complete(itp, on: daysAgo(2), cost: Money(170)).value }
        try step {
            _ = try documents.file(DocumentDraft(title: "Raport ITP", fileName: "raport-itp.jpg", kind: .report, contentType: "public.jpeg",
                                                 pageImages: [try picture("page-back.jpg")], thumbnail: try picture("thumb-back.jpg")),
                                   historyEntry: inspection)
        }
        let rca = try deadline(car, "vehicle.rca")
        try step { try obligations.setDetails(rca, estimatedCost: Money(Decimal(string: "1250.75") ?? 0), reference: "POL-000001") }
        try step { _ = try obligations.setReminderTime(rca, minuteOfDay: 480, startedFrom: nil) }
        let oldPolicy = try step {
            try documents.file(DocumentDraft(title: "Poliță RCA 2025", fileName: "polita-2025.jpg", kind: .policy, contentType: "public.jpeg",
                                             pageImages: [try picture("thumb-back.jpg")]), obligation: rca)
        }
        let newPolicy = try step {
            try documents.file(DocumentDraft(title: "Poliță RCA 2026", fileName: "polita-2026.pdf", kind: .policy, contentType: "com.adobe.pdf",
                                             originalData: try picture("policy.pdf"), documentDate: day(-3)), obligation: rca)
        }
        try step { try documents.supersede(oldPolicy, with: newPolicy) }
        try step { _ = try obligations.snooze(try deadline(car, "vehicle.vignette"), days: 3) }

        // The home, its tenancy (which brings the household's rental declaration), electricity and a guarantee.
        let homeTemplate = try template(BuiltInTemplates.Key.home)
        var homeValues = FieldValues()
        homeValues["home.address"] = .text("Str. Exemplu nr. 7, Cluj-Napoca")
        homeValues["home.area"] = .number(74.5)
        let home = try step {
            try assets.create(name: "Apartament", template: homeTemplate, values: homeValues,
                              obligations: plan(homeTemplate, homeValues, dues: ["home.pad": 31, "home.boilerCheck": 140, "home.gasCheck": 410]))
        }
        try step { _ = try obligations.pause(try deadline(home, "home.gasCheck")) }
        let tenancyTemplate = try template(BuiltInTemplates.Key.tenancy)
        var lease = FieldValues()
        lease["tenancy.start"] = .date(day(-200))
        lease["tenancy.end"] = .date(day(165))
        lease["tenancy.rent"] = .money(Money(2_000))
        lease["tenancy.paymentDay"] = .number(5)
        lease["tenancy.deposit"] = .money(Money(500, currency: "EUR"))
        let tenancy = try step {
            try assets.create(name: "Închiriere apartament", template: tenancyTemplate, values: lease, obligations: plan(tenancyTemplate, lease), parent: home)
        }
        try step { _ = try providers.create(name: "Chiriaș Exemplu", trades: [.tenant], phone: "0700 000 002", linkedTo: [tenancy]) }

        let subscription = try template(BuiltInTemplates.Key.subscription)
        var power = FieldValues()
        power["subscription.provider"] = .text("ENGIE Romania S.A.")
        power[SubscriptionFields.service] = .text(ServiceKind.electricity)
        power["subscription.price"] = .money(Money(Decimal(string: "180.40") ?? 0))
        power["subscription.cycle"] = .text(BillingCycle.monthly)
        let electricity = try step {
            try assets.create(name: "Curent", template: subscription, values: power, obligations: plan(subscription, power), parent: home)
        }
        // A bill's estimated index, then the one read off the meter.
        try step {
            _ = try HouseholdMutations.recordReading(
                PlannedReading(812, on: electricity, at: daysAgo(40), source: .document, unit: .kilowattHours, kind: .electricity, basis: .estimated),
                answer: nil, in: context)
        }
        try step {
            _ = try HouseholdMutations.recordReading(
                PlannedReading(845, on: electricity, at: daysAgo(10), source: .document, unit: .kilowattHours, kind: .electricity, basis: .read),
                answer: nil, in: context)
        }
        // What capture learned of the supplier's bills.
        try step {
            let issuer = IssuerKey(rawValue: "name:ENGIEROMANIASA")
            try IssuerLessons(context: context, now: now).record(
                CaptureLessonLearner.Outcome(issuer: issuer, issuerName: "ENGIE Romania S.A.",
                                             learned: [CaptureLesson(issuer: issuer, kind: .utilityInvoice, field: .dueDate, label: "Ultima zi de plată")],
                                             forgotten: []),
                learnedIn: BuiltInTemplates.Key.subscription)
        }
        let purchase = try template(BuiltInTemplates.Key.purchase)
        var washer = FieldValues()
        washer["purchase.brand"] = .text("Mașină de spălat exemplu")
        washer["purchase.retailer"] = .text("Magazin Exemplu")
        washer["purchase.price"] = .money(Money(Decimal(string: "2199.99") ?? 0))
        washer["purchase.date"] = .date(day(-640))
        try step { _ = try assets.create(name: "Mașină de spălat", template: purchase, values: washer, obligations: plan(purchase, washer), parent: home) }

        // Ana's health, in the locked category, with a weight.
        let healthTemplate = try template(BuiltInTemplates.Key.health)
        var health = FieldValues()
        health["health.bloodType"] = .text("bloodType.aPositive")
        health["health.allergies"] = .text("Fără alergii cunoscute")
        let profile = try step {
            try assets.create(name: "Profil medical Ana", template: healthTemplate, values: health,
                              obligations: plan(healthTemplate, health, dues: ["health.checkup": 45, "health.dentist": 9]))
        }
        try step { _ = try assets.recordMeasurement(on: profile, kind: .bodyWeight, value: 62.5, unit: .kilograms, at: daysAgo(7)) }

        // A category of one's own, counted in engine hours, with rows under Date importante (one secret),
        // a new counter and a deadline of one's own.
        let boats = try step {
            try store.createCustom(name: "Bărci", symbol: "sailboat.fill",
                                   switches: CategorySwitches(hasDocuments: true, service: .init(.engineHours, every: 100)), tint: .teal)
        }
        var boatValues = FieldValues()
        boatValues[CategorySwitches.counterFieldKey(.engineHours)] = .number(210)
        let boat = try step { try assets.create(name: "Barca de pe lac", template: boats, values: boatValues, obligations: plan(boats, boatValues)) }
        try step {
            _ = try assets.setCustomFacts(boat, [
                CustomFact(label: openRowLabel, value: "Ponton 3, locul 12"),
                CustomFact(label: secretRowLabel, value: "0000", isSecret: true),
            ])
        }
        try step { _ = try assets.recordReading(4, on: boat, at: clock.now, source: .person, lowerReading: .newCounter) }
        try step {
            _ = try obligations.create(title: ownDeadline, kind: DeadlineChoice.Importance.reminder.kind, dueDay: day(30), for: boat,
                                       recurrence: .interval(.months(6), anchor: .completion), reminders: DeadlineChoice.reminders(for: .reminder),
                                       notes: "Două baterii AA.")
        }

        // What a newer version wrote, brought in by an import of its archive.
        try DossierArchiveService(container: container, calendar: calendar).importArchive(try newerArchive(), mode: .merge)
        return container
    }

    /// A small archive from a newer version of the app: a category of one's own whose behaviour
    /// and fields this version doesn't fully know, a section with values and a row it doesn't
    /// know, a deadline whose recurrence and reminders carry keys it doesn't know, and a document
    /// whose framing does, its one page a JPEG named `.heic` as archives were written before.
    static func newerArchive() throws -> Data {
        let jpeg = try ArchivePicturesTests.picture("page-back.jpg")
        let category = "custom.7d1e2f30-0000-4000-8000-00000000c011"
        let section = "7d1e2f30-0000-4000-8000-00000000a001"
        let document = "7d1e2f30-0000-4000-8000-00000000d001"
        let page = "vault/\(document)/page-1.heic"
        let made = "2026-11-01T09:00:00Z"
        var files: [String: Data] = [
            DossierV3.Path.templates: Data("""
            [{"key": "\(category)", "name": "Colecții", "symbol": "books.vertical", "tint": "indigo", "heroStyle": "standard",
              "isBuiltIn": false, "version": 0, "homeOrder": 90, "isOnHome": true, "isSensitive": false,
              "pockets": ["upcoming", "documents", "history", "keyFacts"],
              "behavior": {"box": "perSection", "futureBehaviour": "kept"},
              "sections": [{"key": "collection.main", "title": "Colecție", "fields": [
                {"key": "collection.shelf", "label": "Raft", "type": "text", "isEssential": false, "isSensitive": false},
                {"key": "collection.score", "label": "Notă", "type": "stars", "isEssential": false, "isSensitive": false}]}],
              "blueprints": [], "createdAt": "\(made)", "updatedAt": "\(made)"}]
            """.utf8),
            DossierV3.Path.assets: Data("""
            [{"id": "\(section)", "templateKey": "\(category)", "name": "Colecția de timbre", "isExample": false,
              "values": {"collection.shelf": {"type": "text", "value": "A3", "futureNote": "kept"},
                         "collection.place": {"type": "geoPoint", "lat": 44.4268, "lon": 26.1025}},
              "customFacts": [{"id": "7d1e2f30-0000-4000-8000-00000000f001", "label": "Album", "value": "Albastru", "isSensitive": false, "futureColour": "blue"}],
              "createdAt": "\(made)", "updatedAt": "\(made)"}]
            """.utf8),
            DossierV3.Path.obligations: Data("""
            [{"id": "7d1e2f30-0000-4000-8000-00000000b001", "assetId": "\(section)", "title": "Verifică albumele", "kind": "routine",
              "dueDate": "2027-05-01", "status": "active", "isExample": false,
              "recurrence": {"type": "interval", "every": 1, "unit": "year", "anchor": "dueDate", "skipHolidays": true},
              "reminders": {"leadDays": [7], "consequence": "comfort", "graceDays": 0, "followUpAfterLapse": false, "quietHours": true},
              "createdAt": "\(made)", "updatedAt": "\(made)"}]
            """.utf8),
            DossierV3.Path.attachments: Data("""
            [{"id": "\(document)", "title": "Fotografie album", "fileName": "album.heic", "kind": "photo", "contentType": "public.heic",
              "byteCount": \(jpeg.count), "sha256": "\(Hashing.sha256(jpeg))", "pagePaths": ["\(page)"], "isArchived": false,
              "isExample": false, "assetId": "\(section)",
              "framing": {"version": 1, "pages": [{"quarterTurns": 1, "futureFilter": "mono"}], "futureSource": "camera"},
              "createdAt": "\(made)", "updatedAt": "\(made)"}]
            """.utf8),
            page: jpeg,
        ]
        for path in DossierV3.Path.dataFiles where files[path] == nil { files[path] = Data("[]".utf8) }
        let checksums = files.mapValues(Hashing.sha256)
        let manifest: [String: Any] = [
            "format": DossierV3.format, "schemaVersion": 3, "appVersion": "9.0", "platform": "iOS", "exportedAt": made,
            "counts": ["templates": 1, "assets": 1, "obligations": 1, "historyEntries": 0, "serviceItems": 0, "providers": 0,
                       "measurements": 0, "attachments": 1, "issuerLessons": 0],
            "checksums": checksums,
        ]
        files[DossierV3.Path.manifest] = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        return try DosarZipEngine.createArchive(entries: files.keys.sorted().map { DosarZipEngine.Entry(path: $0, data: files[$0]!) })
    }
}

// MARK: - Contents

/// An archive's contents as `expected/` keeps them: the manifest and the data files as
/// written, and every other file (the vault) by path and SHA-256.
struct GoldenContents: Equatable {
    var files: [String: Data]
    var vault: [String: String]

    static let listing = "vault.json"

    static func unpack(_ archive: Data, password: String? = nil) throws -> GoldenContents {
        let plain = try password.map { try ArchiveEncryption.decrypt(archive, password: $0) } ?? archive
        var contents = GoldenContents(files: [:], vault: [:])
        let kept = Set(DossierV3.Path.dataFiles + [DossierV3.Path.manifest])
        for entry in try DosarZipEngine.unpackArchive(plain) {
            if kept.contains(entry.path) { contents.files[entry.path] = entry.data } else { contents.vault[entry.path] = Hashing.sha256(entry.data) }
        }
        return contents
    }

    /// What `expected/` holds.
    static func read(_ folder: URL) throws -> GoldenContents {
        var contents = GoldenContents(files: [:], vault: [:])
        for path in DossierV3.Path.dataFiles + [DossierV3.Path.manifest] {
            let url = folder.appending(path: path)
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) { contents.files[path] = try Data(contentsOf: url) }
        }
        let listing = folder.appending(path: listing)
        if FileManager.default.fileExists(atPath: listing.path(percentEncoded: false)) {
            contents.vault = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: listing))
        }
        return contents
    }

    /// Writes `expected/`: each file as the archive holds it, and the vault's listing.
    func write(to folder: URL) throws {
        try? FileManager.default.removeItem(at: folder)
        for (path, data) in files {
            let url = folder.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try (encoder.encode(vault) + Data("\n".utf8)).write(to: folder.appending(path: Self.listing))
    }

    static func manifest(_ contents: GoldenContents) throws -> DossierV3.Manifest {
        try DossierV3.decoder().decode(DossierV3.Manifest.self, from: try #require(contents.files[DossierV3.Path.manifest]))
    }

    static func objects(_ contents: GoldenContents, _ path: String) throws -> [[String: Any]] {
        guard let data = contents.files[path] else { return [] }
        return try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }

    /// A data file's records by id (a category's by its key), each as an object to compare.
    static func records(_ contents: GoldenContents, _ path: String) throws -> [String: NSDictionary] {
        var byID: [String: NSDictionary] = [:]
        for record in try objects(contents, path) {
            let id = try #require((record["id"] ?? record["key"]) as? String)
            byID[id.lowercased()] = record as NSDictionary
        }
        return byID
    }

    // MARK: Compared by contents

    static var uuid: Regex<Substring> { /[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/ }

    /// The contents with only what must differ from one run to the next left out, each file as
    /// one text to compare:
    /// - **Ids:** the actions make new ones each run. Each is written as the place it takes,
    ///   `id-1`, `id-2`…, counted over the records in an order of their own contents, so the
    ///   same household gives the same text whatever its ids, and every link still says which
    ///   record it points at.
    /// - **`createdAt`:** the moment a record was made, from the clock (the models stamp it
    ///   themselves); every other time is the step's own, the same each run.
    /// - **The app's version** in the manifest, and the checksums of the data files, which
    ///   follow from them (the data files themselves are compared).
    static func canonical(_ contents: GoldenContents) throws -> [String: String] {
        var tokens: [String: String] = [:]
        func token(_ id: String) -> String {
            let key = id.lowercased()
            if let known = tokens[key] { return known }
            let made = "id-\(tokens.count + 1)"
            tokens[key] = made
            return made
        }
        func text(_ value: Any) throws -> String {
            String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed]), as: UTF8.self)
        }
        let uuid = Self.uuid
        func form(_ value: Any, key: String? = nil, ids: (String) -> String) -> Any {
            switch value {
            case let string as String:
                return key == "createdAt" ? "<made>" : string.replacing(uuid) { ids(String($0.output)) }
            case let list as [Any]:
                let items = list.map { form($0, ids: ids) }
                // A list of ids (a firm's sections, a visit's firms) is a set: written in the ids' order.
                if !list.isEmpty, list.allSatisfy({ ($0 as? String)?.wholeMatch(of: uuid) != nil }), let names = items as? [String] {
                    return names.sorted()
                }
                return items
            case let object as [String: Any]:
                var formed: [String: Any] = [:]
                // A key may name a record too (a vault file's path).
                for name in object.keys.sorted() { formed[name.replacing(uuid) { ids(String($0.output)) }] = form(object[name]!, key: name, ids: ids) }
                return formed
            default:
                return value
            }
        }

        // The records of each file, in an order of their contents alone.
        var ordered: [String: [[String: Any]]] = [:]
        for path in DossierV3.Path.dataFiles {
            let blank = try objects(contents, path).map { (record: $0, text: try text(form($0, ids: { _ in "<id>" }))) }
            let sorted = blank.sorted { $0.text < $1.text }
            for (a, b) in zip(sorted, sorted.dropFirst()) where a.text == b.text {
                Issue.record("\(path) has two records that differ only by their ids, so the golden household can't be compared: tell them apart")
            }
            ordered[path] = sorted.map(\.record)
        }
        // Every record's own id first, so a link counts the same whatever the order of the links.
        for path in DossierV3.Path.dataFiles {
            for record in ordered[path] ?? [] {
                for name in ["id", "key"] {
                    for match in ((record[name] as? String) ?? "").matches(of: uuid) { _ = token(String(match.output)) }
                }
            }
        }
        var result: [String: String] = [:]
        for path in DossierV3.Path.dataFiles {
            result[path] = try text(form(ordered[path] ?? [], ids: token))
        }
        let manifestData = try #require(contents.files[DossierV3.Path.manifest])
        var manifest = try #require(try JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
        manifest["appVersion"] = nil
        let checksums = manifest["checksums"] as? [String: String] ?? [:]
        manifest["checksums"] = checksums.filter { !DossierV3.Path.dataFiles.contains($0.key) }
        result[DossierV3.Path.manifest] = try text(form(manifest, ids: token))
        result[listing] = try text(form(contents.vault, ids: token))
        return result
    }
}

private extension URL {
    func creatingDirectory() throws -> URL {
        try FileManager.default.createDirectory(at: self, withIntermediateDirectories: true)
        return self
    }
}
