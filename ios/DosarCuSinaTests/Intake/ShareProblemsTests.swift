import Foundation
import Testing
import UniformTypeIdentifiers
@testable import DosarCuSina

// After a share where some files didn't arrive: the confirmation says how many and why, every
// reason is counted („Fișierul…”, „Fișierele…”), files left untried (nothing it can take, past
// the limit) are told on their own lines, and Setări › Despre lists the share log's failures in
// the same words, with „Golește lista” undone from its toast. Placeholder data only.

@Suite("Share: what didn't arrive is counted")
struct ShareNotArrivedTests {
    @Test func aShareWhereSomeArrivedSaysHowManyDidntAndWhyInTheSameConfirmation() {
        var missed = ShareFailure.Tally()
        missed.add(.couldNotCopy)
        missed.add(.stillInCloud)
        let phase = ShareConfirmation.Phase.saved(count: 2, next: .tapNotice, notArrived: missed.missed)
        let confirmation = ShareConfirmation(phase)
        #expect(confirmation.title == "Am primit 2 acte", "What arrived leads")
        #expect(confirmation.message == "Atinge notificarea ca să continui. Te așteaptă în aplicație, la De verificat.")
        #expect(confirmation.note == "2 fișiere sunt încă în iCloud. Nu le-am putut descărca acum. Deschide-le o dată în Fișiere, apoi trimite-le din nou.",
                "How many didn't, the most telling reason, and what to do")
        #expect(confirmation.action == .close)

        let one = ShareConfirmation(.saved(count: 1, next: .openApp, notArrived: .init(files: 1, failure: .noRoom)))
        #expect(one.note == "Un fișier nu a mai încăput pe telefon. Fă loc din Configurări › General › Spațiu iPhone, apoi trimite-l din nou.")
        #expect(ShareConfirmation(.saved(count: 1, next: .openApp)).note == nil, "Nothing more to say when everything arrived")
    }

    @Test func theTallyCountsFilesAndKeepsTheMostTellingReason() {
        var tally = ShareFailure.Tally()
        #expect(tally.missed == nil)
        #expect(ShareConfirmation.Phase.nothingSaved(tally.missed) == .unsupported, "Nothing failed and nothing arrived: nothing it can read")
        tally.add(.notHandedOver)
        tally.add(.tooLarge, files: 3) // photos sorted into one document that couldn't be kept
        #expect(tally.missed == ShareFailure.Missed(files: 4, failure: .tooLarge))
        #expect(ShareConfirmation.Phase.nothingSaved(tally.missed) == .failed(.tooLarge, count: 4))
    }

    @Test func everyReasonIsCountedForSeveralFiles() {
        for failure in ShareFailure.allCases {
            let one = ShareConfirmation(.failed(failure, count: 1))
            let several = ShareConfirmation(.failed(failure, count: 3))
            #expect(one == ShareConfirmation(.failed(failure)), "One file is the default")
            for confirmation in [one, several] {
                #expect(!confirmation.title.isEmpty && !confirmation.title.contains("%"))
                #expect(confirmation.message?.hasSuffix(".") == true)
                #expect(confirmation.message?.contains("%") == false && confirmation.message?.contains("cele 3") == false,
                        "The number stays out of the words: „Fișierele…”")
            }
            if one.title.hasPrefix("Fișierul") {
                #expect(several.title.hasPrefix("Fișierele"), "\(failure): „\(several.title)”")
            }
            if one.message != several.message {
                for pronoun in ["-l ", "-l.", "-l,", "l-am", "l-ai", "să-l"] {
                    #expect(several.message?.contains(pronoun) == false, "\(failure): „\(several.message ?? "")” speaks of one file")
                }
            }
            // How many didn't arrive, beside what did: a word for one, „de” from 20.
            #expect(ShareFailureWording.cause(failure, count: 1).contains("un fișier") || ShareFailureWording.cause(failure, count: 1).hasPrefix("Un fișier"))
            #expect(ShareFailureWording.cause(failure, count: 3).contains("3 fișiere"))
            #expect(ShareFailureWording.cause(failure, count: 20).contains("20 de fișiere"))
        }
        #expect(ShareConfirmation(.failed(.stillInCloud, count: 2)).title == "Fișierele sunt încă în iCloud")
        #expect(ShareConfirmation(.failed(.stillInCloud, count: 2)).message == "Nu le-am putut descărca acum. Deschide-le o dată în Fișiere, apoi trimite-le din nou.")
        #expect(ShareConfirmation(.failed(.notHandedOver, count: 2)).title == "Nu s-au trimis")
        #expect(ShareConfirmation(.failed(.notHandedOver, count: 1)).title == "Nu s-a trimis")
        #expect(ShareConfirmation(.failed(.tooLarge, count: 2)).title == "Fișierele sunt prea mari")
    }
}

@Suite("Settings: problems receiving shared files")
struct ShareProblemsPageTests {
    private static let calendar = Calendar.dosar(in: TimeZone(identifier: "Europe/Bucharest")!)

    private static func moment(_ day: Int, _ hour: Int, _ minute: Int, month: Int = 11, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private static func entry(_ failure: ShareFailure, at date: Date) -> ShareFailureLog.Entry {
        ShareFailureLog.Entry(at: date, failure: failure, attempts: [.init(way: "link", failure: failure, domain: NSCocoaErrorDomain, code: 4)])
    }

    @Test func theLatestFailuresAreListedFirstInTheShareSheetsWords() {
        let now = Self.moment(18, 15, 0)
        let entries = [
            Self.entry(.noRoom, at: Self.moment(2, 9, 30)),
            Self.entry(.stillInCloud, at: Self.moment(18, 14, 5)),
            Self.entry(.noAccess, at: Self.moment(17, 9, 30)),
            Self.entry(.tooLarge, at: Self.moment(12, 8, 0, year: 2025)),
        ]
        let rows = ShareProblems.rows(entries, now: now, calendar: Self.calendar)
        #expect(rows.map(\.title) == ["Fișierul e încă în iCloud", "Nu pot deschide fișierul", "Nu mai e loc pe telefon", "Fișierul e prea mare"])
        #expect(rows.map(\.when) == ["Azi la 14:05", "Ieri la 09:30", "Pe 2 noiembrie la 09:30", "Pe 12 noiembrie 2025 la 08:00"])
        #expect(rows[0].advice == ShareFailureWording.advice(.stillInCloud), "What to do, as the share sheet said it")
        #expect(Set(rows.map(\.id)).count == rows.count)
    }

    @Test func theRowInDespreShowsOnlyWhileSomethingDidntArrive() {
        #expect(!ShareProblems.showsRow([]))
        #expect(ShareProblems.showsRow([Self.entry(.offline, at: Self.moment(18, 10, 0))]))
        #expect(SettingsStatus.shareProblems(1) == "Un fișier nu a ajuns")
        #expect(SettingsStatus.shareProblems(3) == "3 fișiere nu au ajuns")
        #expect(SettingsStatus.shareProblems(20) == "20 de fișiere nu au ajuns")
        #expect(ShareProblemsWording.title == "Probleme la primire")
        #expect(ShareProblemsWording.empty == "Nicio problemă la primire.")
    }

    @Test func thePageReadsTheShareLogAndShowsNoNameOrPath() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "dosar-share-problems-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let inbox = ShareInbox(directory: folder)
        #expect(ShareProblems.read(inbox).isEmpty, "No log: nothing to show, and no row")
        #expect(ShareProblems.read(nil).isEmpty)

        let named = NSError(domain: "com.exemplu.Factura ENGIE", code: 3)
        ShareFailureLog.record(ShareFailureLog.Entry(at: Self.moment(18, 14, 5), failure: .couldNotCopy,
                                                     attempts: [ShareFailureLog.Attempt(way: "file", error: named)]), in: inbox)
        let entries = ShareProblems.read(inbox)
        #expect(entries.count == 1)
        let row = try #require(ShareProblems.rows(entries, now: Self.moment(18, 15, 0), calendar: Self.calendar).first)
        for words in [row.title, row.when, row.advice] {
            #expect(!words.contains("Factura") && !words.contains("/"), "Never a file's name or path: „\(words)”")
        }
        #expect(row.title == "Nu s-a trimis")
    }
}

private func shareLogFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "dosar-share-log-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func failureEntry(_ failure: ShareFailure, at seconds: TimeInterval, files: Int = 1) -> ShareFailureLog.Entry {
    ShareFailureLog.Entry(at: Date(timeIntervalSince1970: seconds), failure: failure,
                          attempts: [.init(way: "file", failure: failure, domain: NSCocoaErrorDomain, code: 4)], files: files)
}

@Suite("Share: files left untried are counted too")
struct ShareLeftUntriedTests {
    /// A note shared as text, which the inbox takes.
    @MainActor private static func note() -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.plainText.identifier, visibility: .all) { completion in
            completion(Data("Notă despre factura ENGIE Romania S.A.".utf8), nil)
            return nil
        }
        return provider
    }

    /// A web link, which the inbox can't take.
    @MainActor private static func webLink() -> NSItemProvider {
        NSItemProvider(item: URL(string: "https://exemplu.ro/factura")! as NSURL, typeIdentifier: UTType.url.identifier)
    }

    @Test func whatItCantTakeAndWhatIsPastTheLimitAreToldOnTheirOwnLines() {
        var tally = ShareFailure.Tally()
        tally.add(.stillInCloud)
        tally.add(.unsupportedType)
        tally.add(.overFileLimit, files: 3)
        let missed = tally.missed
        #expect(missed?.failed == .init(files: 1, failure: .stillInCloud), "Only the files tried in vain share the most telling reason")
        #expect(missed?.left == [.init(files: 1, failure: .unsupportedType), .init(files: 3, failure: .overFileLimit)])
        let confirmation = ShareConfirmation(.saved(count: 20, next: .openApp, notArrived: missed))
        #expect(confirmation.note == [
            "Un fișier e încă în iCloud. Nu l-am putut descărca acum. Deschide-l o dată în Fișiere, apoi trimite-l din nou.",
            "Nu pot primi un fișier. Pot primi poze, PDF-uri și text. Trimite factura sau actul ca poză sau PDF.",
            "3 fișiere au rămas pe dinafară. Trimite cel mult 20 de fișiere odată, apoi restul separat.",
        ].joined(separator: "\n"))

        var many = ShareFailure.Tally()
        many.add(.unsupportedType)
        many.add(.unsupportedType)
        many.add(.overFileLimit, files: 25)
        #expect(ShareConfirmation(.saved(count: 1, next: .openApp, notArrived: many.missed)).note == [
            "Nu pot primi 2 fișiere. Pot primi poze, PDF-uri și text. Trimite factura sau actul ca poză sau PDF.",
            "25 de fișiere au rămas pe dinafară. Trimite cel mult 20 de fișiere odată, apoi restul separat.",
        ].joined(separator: "\n"), "Counted with the catalog's plural forms")
        #expect(ShareFailureWording.cause(.overFileLimit, count: 1) == "Un fișier a rămas pe dinafară.")
        #expect(ShareFailureWording.advice(.overFileLimit).contains("\(ShareInbox.maxFiles) de fișiere"), "The limit is the inbox's own")
    }

    @Test func whenNothingArrivedTodaysMessagesStay() {
        var unsupported = ShareFailure.Tally()
        unsupported.add(.unsupportedType)
        unsupported.add(.unsupportedType)
        let phase = ShareConfirmation.Phase.nothingSaved(unsupported.missed)
        #expect(phase == .unsupported)
        #expect(ShareConfirmation(phase).title == "Nu pot primi asta")
        #expect(ShareConfirmation(phase).message == "Pot primi poze, PDF-uri și text. Trimite factura sau actul ca poză sau PDF.")
        #expect(ShareConfirmation(phase).message == ShareFailureWording.advice(.unsupportedType), "One place for the words")

        var tooLarge = ShareFailure.Tally()
        tooLarge.add(.unsupportedType)
        tooLarge.add(.tooLarge)
        #expect(ShareConfirmation.Phase.nothingSaved(tooLarge.missed) == .failed(.tooLarge, count: 1),
                "Counted by the file tried in vain, as before")
        #expect(ShareFailure.Missed(files: 2, failure: .unsupportedType).failed == nil)
        #expect(Array(ShareFailure.mostTellingFirst.suffix(ShareFailure.leftUntried.count)) == ShareFailure.leftUntried,
                "A file left untried is told after every way's failure")
        #expect(ShareFailure.allCases.filter(\.isLeftUntried) == ShareFailure.leftUntried)
    }

    @MainActor
    @Test func aShareCountsWhatItCantTakeAndLogsItAsAKind() async throws {
        let folder = try shareLogFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let inbox = ShareInbox(directory: folder)
        let holding = try inbox.makeStagingFolder()

        let share = await ShareReceiving.receiveAll([Self.note(), Self.webLink(), Self.note()], into: holding, log: inbox)
        #expect(share.received.map(\.kind) == [.text, .text])
        #expect(share.missed.missed == ShareFailure.Missed(files: 1, failure: .unsupportedType))
        let log = inbox.failureLog()
        #expect(log.map(\.failure) == [.unsupportedType])
        #expect(log.first?.attempts.map(\.way) == ["kind"])
        #expect(log.first?.attempts.map(\.domain) == ["none"], "Kinds only: nothing the sender wrote")
    }

    @MainActor
    @Test func filesPastTheLimitAreNeverAskedForAndAreCountedTogether() async throws {
        let folder = try shareLogFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let inbox = ShareInbox(directory: folder)
        let holding = try inbox.makeStagingFolder()

        let providers = (0 ..< ShareInbox.maxFiles + 2).map { _ in Self.note() }
        let share = await ShareReceiving.receiveAll(providers, into: holding, log: inbox)
        #expect(share.received.count == ShareInbox.maxFiles)
        #expect(share.missed.missed == ShareFailure.Missed(files: 2, failure: .overFileLimit))
        let log = inbox.failureLog()
        #expect(log.count == 1, "One entry for every file past the limit, so the log keeps the others")
        #expect(log.first?.failure == .overFileLimit)
        #expect(log.first?.files == 2)
        #expect(ShareProblems.files(log) == 2)
        #expect(SettingsStatus.shareProblems(ShareProblems.files(log)) == "2 fișiere nu au ajuns")
        let row = try #require(ShareProblems.rows(log).first)
        #expect(row.title == "2 fișiere au rămas pe dinafară")
        #expect(row.advice == "Trimite cel mult 20 de fișiere odată, apoi restul separat.")
    }

    @Test func aLogKeptBeforeFilesWereCountedReadsAsOneFileEach() throws {
        let folder = try shareLogFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let inbox = ShareInbox(directory: folder)
        let earlier = #"[{"at":"2026-11-18T12:05:00Z","failure":"stillInCloud","attempts":[{"way":"link","failure":"stillInCloud","domain":"NSCocoaErrorDomain","code":4}]}]"#
        try Data(earlier.utf8).write(to: folder.appending(path: ShareInbox.failureLogName))
        let log = inbox.failureLog()
        #expect(log.map(\.files) == [1])
        #expect(log.map(\.failure) == [.stillInCloud])
    }
}

// One at a time: emptying the log posts a notification another test of this suite counts.
@Suite("Settings: „Golește lista” empties the share log", .serialized)
struct ShareProblemsClearTests {
    @Test func emptyingTheListTakesTheRowAwayAndItsUndoBringsItBack() throws {
        let folder = try shareLogFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let inbox = ShareInbox(directory: folder)
        ShareFailureLog.record(failureEntry(.noRoom, at: 1_000), in: inbox)
        ShareFailureLog.record(failureEntry(.tooLarge, at: 2_000, files: 3), in: inbox)
        #expect(ShareProblems.showsRow(ShareProblems.read(inbox)))

        let heard = Heard()
        let observer = NotificationCenter.default.addObserver(forName: ShareFailureLog.didChangeNotification, object: nil, queue: nil) { _ in heard.count += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        let removed = try ShareProblems.clear(inbox)
        #expect(removed.map(\.failure) == [.noRoom, .tooLarge], "Kept for the toast's „Anulează”")
        #expect(ShareProblems.read(inbox).isEmpty)
        #expect(!ShareProblems.showsRow(ShareProblems.read(inbox)), "Despre's row goes")
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: ShareInbox.failureLogName).path(percentEncoded: false)),
                "Nothing is left behind")
        #expect(heard.count == 1, "Despre and the page read the log again")

        // The share fails again before „Anulează”: both are kept, in time order.
        ShareFailureLog.record(failureEntry(.offline, at: 3_000), in: inbox)
        try ShareProblems.putBack(removed, in: inbox)
        #expect(ShareProblems.read(inbox).map(\.failure) == [.noRoom, .tooLarge, .offline])
        #expect(ShareProblems.files(ShareProblems.read(inbox)) == 5)
        #expect(heard.count == 2)

        #expect(try ShareProblems.clear(nil).isEmpty, "No App Group: nothing to empty")
        #expect(ShareProblemsWording.clear == "Golește lista")
        #expect(ShareProblemsWording.clearLabel == "Golește lista de probleme la primire")
    }

    @Test func puttingBackKeepsTheLatestOnly() throws {
        let removed = (0 ..< ShareFailureLog.kept).map { failureEntry(.stillInCloud, at: TimeInterval($0)) }
        let since = [failureEntry(.noAccess, at: 10_000)]
        let merged = ShareFailureLog.merged(removed, since)
        #expect(merged.count == ShareFailureLog.kept)
        #expect(merged.last?.failure == .noAccess, "The newest stays")
        #expect(merged.first?.at == Date(timeIntervalSince1970: 1), "The oldest goes")
        #expect(ShareFailureLog.merged(since, since) == since, "Each entry once")
    }

    @Test func theShareWritingWhileTheListIsEmptiedLosesNothingAndBringsNothingBack() throws {
        let folder = try shareLogFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let inbox = ShareInbox(directory: folder)
        let written = (0 ..< 16).map { failureEntry(.couldNotCopy, at: TimeInterval(1_000 + $0)) }
        let removed = Removed()
        DispatchQueue.concurrentPerform(iterations: written.count + 1) { index in
            if index == written.count / 2 {
                removed.entries = (try? ShareFailureLog.clear(in: inbox)) ?? []
            } else {
                ShareFailureLog.record(written[index < written.count / 2 ? index : index - 1], in: inbox)
            }
        }
        let left = inbox.failureLog()
        #expect(Set(removed.entries).isDisjoint(with: left), "An entry the list was emptied of never comes back")
        #expect(Set(removed.entries).union(left) == Set(written), "No failure kept meanwhile is lost")
        #expect(removed.entries.count + left.count == written.count)
    }
}

/// Counts what a test heard, from whichever thread posts.
private final class Heard: @unchecked Sendable {
    var count = 0
}

/// What an emptying took, from the thread that took it.
private final class Removed: @unchecked Sendable {
    var entries: [ShareFailureLog.Entry] = []
}
