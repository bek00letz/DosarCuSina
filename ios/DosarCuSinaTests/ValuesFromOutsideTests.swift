import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// What comes from outside the phone (a backup, another device, a file) never stops the app:
/// each value is held to what the app can work with where it is read, and an archive is checked
/// against one set of limits before a byte of it is unpacked. "Înlocuiește tot" replaces the
/// binder in place, so every record stays the copy it is. Every value is a placeholder.
@MainActor
@Suite("Values from outside")
struct ValuesFromOutsideTests {
    private let calendar = Calendar.bucharest

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    /// The golden household, edited as `edit` says, brought into an empty binder.
    private func household(editing edit: @escaping (inout [String: Data]) -> Void) throws -> ModelContainer {
        let container = try makeInMemoryContainer()
        let archive = try Fixtures.archive("dosar-v3/household", editing: edit)
        try DossierArchiveService(container: container, calendar: calendar).importArchive(archive, mode: .replace)
        return container
    }

    // MARK: How often something repeats

    @Test("A repeat longer than anything a household waits for is held to a hundred years, wherever it is read")
    func aRepeatIsHeldToAHundredYears() throws {
        let rule = try decode(RecurrenceRule.self, #"{"type": "interval", "every": 9223372036854775807, "unit": "week", "anchor": "dueDate"}"#)
        guard case .interval(let interval, _) = rule else { Issue.record("Read as an interval"); return }
        #expect(interval.every == RecurrenceInterval.longest(in: .week))

        let due = CalendarDay("2026-11-17")
        for unit in RecurrenceInterval.Unit.allCases {
            let longest = RecurrenceRule.interval(RecurrenceInterval(every: .max, unit: unit), anchor: .dueDate)
            #expect(RecurrenceEngine.cycleStart(endingOn: due, rule: longest, calendar: calendar).map { $0 < due } == true)
            #expect(RecurrenceEngine.nextDue(after: due, completedOn: due, rule: longest, calendar: calendar).map { $0.day > due } == true)
            #expect(RecurrenceInterval(every: .min, unit: unit).every == 1)
        }
        // Read on its own (a first due date "after an interval"), the same bounds.
        #expect(try decode(RecurrenceInterval.self, #"{"every": 9223372036854775807, "unit": "year"}"#).every == 100)
        guard case .afterInterval(let after) = try decode(FirstDueRule.self, #"{"type": "afterInterval", "every": 9223372036854775807, "unit": "month"}"#) else {
            Issue.record("Read as an interval"); return
        }
        #expect(after.every == RecurrenceInterval.longest(in: .month))

        // The form's stepper goes no further.
        let choice = try #require(RepeatChoice(rule: rule))
        #expect(choice.everyRange.upperBound == RecurrenceInterval.longest(in: .week))
        #expect(RepeatChoice(frequency: .day, every: 500).everyRange.upperBound == 500, "A larger number a rule has stays offered")
    }

    @Test("A counter's step from outside stays a number every calculation can use")
    func aCounterStepIsHeld() throws {
        let rule = try decode(RecurrenceRule.self, #"{"type": "metric", "every": 1e300, "unit": "km"}"#)
        guard case .metric(let every, _, _) = rule else { Issue.record("Read as a counter's rule"); return }
        #expect(every == RecurrenceRule.longestMetricStep)
        #expect(CategorySwitches.every(in: rule) == Int(RecurrenceRule.longestMetricStep))
        #expect(RecurrenceRule.allowedMetricStep(-1e300) == 0)
    }

    @Test("A job projected further than anything repeats is estimated by time instead")
    func aFarProjectionIsNoEstimate() {
        #expect(MaintenanceLog.days(42) == 42)
        #expect(MaintenanceLog.days(1e30) == nil)
        #expect(MaintenanceLog.days(.infinity) == nil)
        #expect(MaintenanceLog.days(.nan) == nil)
    }

    // MARK: A category's place and name

    @Test("A place on the binder at the very end still leaves room for the next category")
    func aFarPlaceLeavesRoom() throws {
        let container = try household { files in
            NewerVersionTests.rewrite(&files, DossierV3.Path.templates) { templates in
                templates[0].set("homeOrder", .int(.min))
                templates[1].set("homeOrder", .int(.max))
            }
        }
        let context = ModelContext(container)
        let templates = try context.fetch(FetchDescriptor<CategoryTemplate>())
        #expect(templates.first { $0.key == BuiltInTemplates.Key.vehicle }?.homeOrder == -CategoryOrder.farthest)
        #expect(templates.first(where: \.isCustom)?.homeOrder == CategoryOrder.farthest)
        #expect(templates.allSatisfy { abs($0.homeOrder) <= CategoryOrder.farthest + BuiltInTemplates.all.count })

        let made = try TemplateStore(context: context).createCustom(name: "Rulota", symbol: "box.truck", pockets: SectionPocket.standard)
        #expect(made.homeOrder > CategoryOrder.farthest, "It goes last")
        try TemplateStore(context: context).installBuiltIns()
    }

    @Test("A category of one's own takes its own name for its sections, whatever an archive says")
    func aCategoryOfOnesOwnHasNoSingular() throws {
        let container = try household { files in
            NewerVersionTests.rewrite(&files, DossierV3.Path.templates) { templates in
                templates[1].set("behavior", ["singular": ["name": "Barca", "gender": "feminine"]])
            }
        }
        let context = ModelContext(container)
        let boats = try #require(try context.fetch(FetchDescriptor<CategoryTemplate>()).first(where: \.isCustom))
        #expect(boats.behavior.singular == nil)
        #expect(boats.definition.sectionName == "Bărci")
    }

    @Test("A gender from a newer build keeps the name a section is called")
    func anUnknownGenderKeepsTheName() throws {
        let behavior = try decode(CategoryBehavior.self, #"{"visit": "none", "singular": {"name": "Mașina", "gender": "commonFuture"}}"#)
        #expect(behavior.singular == SectionSingular("Mașina", .masculineOrNeuter))
        // What it wrote goes out again as written.
        let kept = try decode(KeptObject<CategoryBehavior>.self, #"{"visit": "none", "singular": {"name": "Mașina", "gender": "commonFuture"}}"#)
        let written = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(kept))
        #expect(written["singular"]?["gender"] == "commonFuture")
    }

    // MARK: A reminder's time

    @Test("A reminder time from a backup stays within the day, as the page shows it and the reminder fires")
    func aReminderTimeStaysWithinTheDay() throws {
        let container = try household { files in
            NewerVersionTests.rewrite(&files, DossierV3.Path.obligations) { obligations in
                obligations[0].set("reminderMinuteOfDay", .int(-5))
                obligations[1].set("reminderMinuteOfDay", .int(1_500))
            }
        }
        let context = ModelContext(container)
        let minutes = Set(try context.fetch(FetchDescriptor<Obligation>()).compactMap(\.reminderMinuteOfDay))
        #expect(minutes == [0, 24 * 60 - 1])
        let day = CalendarDay("2026-11-17")
        #expect(ReminderPlanner.fireDate(day: day, minuteOfDay: 1_500, calendar: calendar) == day.moment(atMinute: 24 * 60 - 1, in: calendar),
                "Never a minute of the next day")
    }

    // MARK: Archives

    @Test("An archive whose files together unpack past the limit is refused before any is read, both ways")
    func theWholeUnpackedSizeIsLimited() throws {
        let entries: [DosarZipEngine.Entry] = [.init(path: "a.bin", data: Data(count: 10_000)), .init(path: "b.bin", data: Data(count: 10_000))]
        let archive = try DosarZipEngine.createArchive(entries: entries)
        let limits = DosarZipEngine.Limits(maxEntries: 10, maxEntryBytes: 20_000, maxUnpackedBytes: 15_000)
        #expect(throws: DosarZipEngine.ZipError.unpacksTooLarge) { try DosarZipEngine.unpackArchive(archive, limits: limits) }
        // The summary step reads the same directory first, so it refuses before checking a file.
        #expect(throws: DosarZipEngine.ZipError.unpacksTooLarge) {
            try ArchiveFile.holding(archive) { try DossierArchiveReader.summary(contentsOf: $0, limits: limits) }
        }
        // The writer refuses what its reader would.
        let writer = DosarZipEngine.Writer(sink: MemoryByteSink(), limits: limits)
        try writer.add(path: "a.bin", data: Data(count: 10_000), modifiedDate: Date())
        #expect(throws: DosarZipEngine.ZipError.tooLargeToWrite) { try writer.add(path: "b.bin", data: Data(count: 10_000), modifiedDate: Date()) }
        #expect(DosarZipEngine.ZipError.unpacksTooLarge.errorDescription?.isEmpty == false)

        let standard = DosarZipEngine.Limits.standard
        #expect(standard.maxUnpackedBytes >= 2 * standard.maxArchiveBytes, "Well beyond what a binder of photos and papers unpacks to")
    }

    @Test("An archive whose files claim the same bytes is refused")
    func overlappingFilesAreRefused() throws {
        var archive = try DosarZipEngine.createArchive(entries: [
            .init(path: "a.bin", data: Data(repeating: 1, count: 100)),
            .init(path: "b.bin", data: Data(repeating: 2, count: 100)),
        ])
        #expect(try DosarZipEngine.unpackArchive(archive).count == 2)
        // The second file's directory record says it starts where the first does.
        let signature = Data([0x50, 0x4b, 0x01, 0x02])
        let first = try #require(archive.range(of: signature))
        let second = try #require(archive.range(of: signature, in: first.upperBound..<archive.endIndex))
        archive.replaceSubrange((second.lowerBound + 42)..<(second.lowerBound + 46), with: [0, 0, 0, 0])
        #expect(throws: DosarZipEngine.ZipError.overlappingEntries) { try DosarZipEngine.unpackArchive(archive) }
        #expect(DosarZipEngine.ZipError.overlappingEntries.errorDescription?.isEmpty == false)
    }

    /// A protected archive that says it is larger than its chunks can be counted.
    private final class EndlessSource: ArchiveByteSource {
        let header: Data
        let size: Int
        init(header: Data, size: Int) {
            self.header = header
            self.size = size
        }

        func read(at offset: Int, count: Int) throws -> Data {
            guard offset == 0 else { return Data(count: count) }
            return header.prefix(count)
        }
    }

    @Test("A protected archive with more chunks than can be counted is refused, never a stop")
    func tooManyChunksAreRefused() throws {
        var header = ArchiveEncryption.magic
        header.append(ArchiveEncryption.version)
        header.append(ArchiveEncryption.pbkdf2SHA256)
        header.append(contentsOf: [0, 0, 0, 1])          // One round.
        header.append(Data(count: ArchiveEncryption.saltSize))
        header.append(contentsOf: [0, 0, 0, 1])          // Chunks of one byte.
        header.append(Data(count: ArchiveEncryption.noncePrefixSize))
        let sealedChunk = 1 + ArchiveEncryption.tagSize
        let source = EndlessSource(header: header, size: ArchiveEncryption.headerSize + sealedChunk * (ArchiveEncryption.maxChunks + 1))
        #expect(throws: DosarZipEngine.ZipError.sizeLimitExceeded) { try ArchiveEncryption.DecryptingSource(source, password: "parola-exemplu") }
    }

    @Test("Backups an earlier run left in the temporary folder go at launch; nothing else does")
    func leftoverBackupsGoAtLaunch() throws {
        let directory = URL.temporaryDirectory.appending(path: "leftovers-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let export = BackupFiles.exportFolder(in: directory)
        try FileManager.default.createDirectory(at: export, withIntermediateDirectories: true)
        try Data("placeholder".utf8).write(to: export.appending(path: "Dosar cu Șină 2026-11-17.dosar"))
        let copy = BackupFiles.importCopy(in: directory)
        try Data("placeholder".utf8).write(to: copy)
        try FileManager.default.createDirectory(at: copy.deletingPathExtension().appendingPathExtension("files"), withIntermediateDirectories: true)
        try Data("placeholder".utf8).write(to: directory.appending(path: "altceva.txt"))

        BackupFiles.removeLeftovers(in: directory)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)) == ["altceva.txt"])
    }

    // MARK: "Înlocuiește tot"

    @Test("Replacing everything keeps every record the copy it is, so another device's join finds nothing to join")
    func replacingKeepsEachCopy() throws {
        let context = try makeContext()
        let container = context.container
        let car = Asset(name: "VW Golf 2018", templateKey: BuiltInTemplates.Key.vehicle)
        let rca = Obligation(title: "RCA", kind: .insurance, dueDay: CalendarDay("2027-07-15"))
        context.insert(car)
        context.insert(rca)
        rca.asset = car
        try context.save()
        let service = DossierArchiveService(container: container, calendar: calendar)
        let backup = try service.exportData()

        // Changed after the backup, and something only here.
        car.name = "Doar aici"
        let other = Asset(name: "Bicicletă exemplu", templateKey: BuiltInTemplates.Key.other)
        context.insert(other)
        try context.save()
        func copies() throws -> [UUID: Set<UUID>] {
            let fresh = ModelContext(container)
            var names: [UUID: Set<UUID>] = [:]
            for asset in try fresh.fetch(FetchDescriptor<Asset>()) { names[asset.id, default: []].insert(asset.copyID ?? UUID()) }
            for obligation in try fresh.fetch(FetchDescriptor<Obligation>()) { names[obligation.id, default: []].insert(obligation.copyID ?? UUID()) }
            for template in try fresh.fetch(FetchDescriptor<CategoryTemplate>()) { names[UUID(), default: []].insert(template.copyID ?? UUID()) }
            return names
        }
        let before = try copies()

        try service.importArchive(backup, mode: .replace)
        let after = try copies()
        let fresh = ModelContext(container)
        #expect(try fresh.fetch(FetchDescriptor<Asset>()).map(\.name) == ["VW Golf 2018"], "The backup's values, and what it didn't have is gone")
        #expect(after[car.id] == before[car.id], "The car is the same copy it was")
        #expect(after[rca.id] == before[rca.id])
        #expect(after[other.id] == nil)
        #expect(Set(try fresh.fetch(FetchDescriptor<CategoryTemplate>()).compactMap(\.copyID)).isSubset(of: Set(before.values.joined())),
                "Every category is the copy it was")

        // Another device that still has the records as they were sees each one changed, never a
        // second copy of it: put together, every id has one copy, and the join has nothing to do.
        for id in [car.id, rca.id] {
            #expect(before[id, default: []].union(after[id, default: []]).count == 1)
        }
        #expect(try !RecordsMeet.join(in: PersistenceController.context(in: container)))
    }
}
