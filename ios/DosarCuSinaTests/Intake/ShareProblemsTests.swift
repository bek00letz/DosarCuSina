import Foundation
import Testing
@testable import DosarCuSina

// After a share where some files didn't arrive: the confirmation says how many and why, every
// reason is counted („Fișierul…”, „Fișierele…”), and Setări › Despre lists the share log's
// failures in the same words. Placeholder data only.

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
