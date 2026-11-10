import Foundation
import Testing
@testable import DosarCuSina

/// When a date can fall on each kind of document, and how two-digit years take their
/// century from those windows. Placeholder data only.
@Suite("Plausible dates")
struct CapturePlausibilityTests {

    /// 2 November 2026.
    let now = Date(timeIntervalSince1970: 1_793_577_600)
    let today = CalendarDay(printedYear: 2026, month: 11, day: 2)!

    private func day(_ year: Int, _ month: Int, _ day: Int) -> CalendarDay { CalendarDay(printedYear: year, month: month, day: day)! }

    private func field(_ key: CaptureFieldKey, _ value: CalendarDay, _ tier: CaptureTier = .heuristic, confidence: Double = 0.8) -> CaptureField {
        CaptureField(key: key, value: .day(value), confidence: confidence, tier: tier)
    }

    // MARK: Windows

    @Test("Two-digit years take the century their window allows")
    func centuries() {
        let birth = CaptureConsistency.window(for: .birthDate, kind: .passport, today: today)
        #expect(birth.resolve(twoDigitYear: 52, month: 3, day: 1) == day(1952, 3, 1))
        #expect(birth.resolve(twoDigitYear: 25, month: 3, day: 1) == day(2025, 3, 1))
        #expect(birth.resolve(twoDigitYear: 27, month: 3, day: 1) == day(1927, 3, 1))

        let expiry = CaptureConsistency.window(for: .expiryDate, kind: .passport, today: today)
        #expect(expiry.resolve(twoDigitYear: 6, month: 3, day: 12) == day(2006, 3, 12))
        #expect(expiry.resolve(twoDigitYear: 34, month: 3, day: 12) == day(2034, 3, 12))
        // Outside every century the window allows: the nearest, so the rules drop it.
        #expect(expiry.resolve(twoDigitYear: 50, month: 3, day: 12) == day(2050, 3, 12))

        let issue = CaptureConsistency.window(for: .issueDate, kind: .identityCard, today: today)
        #expect(issue.resolve(twoDigitYear: 18, month: 3, day: 12) == day(2018, 3, 12))
        #expect(issue.resolve(twoDigitYear: 8, month: 3, day: 12) == day(2008, 3, 12))
    }

    // MARK: Rules

    @Test("A passport that would expire in 1906 has no expiry")
    func passportExpiringIn1906() {
        let resolved = CaptureConsistency.resolve([field(.expiryDate, day(1906, 3, 12))], kind: .passport, today: today)
        #expect(resolved.fields.isEmpty)
        #expect(resolved.dropped == [.expiryDate])
    }

    @Test("An identity document's expiry is between 2000 and 15 years from today, whichever tier read it")
    func expiryWindow() {
        for tier in CaptureTier.allCases {
            let early = CaptureConsistency.resolve([field(.expiryDate, day(1999, 12, 31), tier)], kind: .identityCard, today: today)
            #expect(early.fields.isEmpty, "\(tier)")
            let late = CaptureConsistency.resolve([field(.expiryDate, day(2042, 1, 1), tier)], kind: .drivingLicence, today: today)
            #expect(late.fields.isEmpty, "\(tier)")
        }
        let expired = CaptureConsistency.resolve([field(.expiryDate, day(2012, 4, 15))], kind: .passport, today: today)
        #expect(expired.fields.count == 1)
        let fine = CaptureConsistency.resolve([field(.expiryDate, day(2034, 4, 15))], kind: .passport, today: today)
        #expect(fine.fields.first?.needsCheck == false)
        // Other documents keep their own dates: a 30-year mortgage-style expiry is not judged here.
        let policy = CaptureConsistency.resolve([field(.expiryDate, day(2056, 1, 1))], kind: .insurancePolicy, today: today)
        #expect(policy.fields.count == 1)
    }

    @Test("An issue date isn't in the future or before the birth date; long ago on an identity document asks for a look")
    func issueWindow() {
        let future = CaptureConsistency.resolve([field(.issueDate, day(2027, 1, 1))], kind: .passport, today: today)
        #expect(future.fields.isEmpty)

        let beforeBirth = CaptureConsistency.resolve([
            field(.birthDate, day(1990, 5, 20), .deterministic, confidence: 0.97),
            field(.issueDate, day(1985, 1, 1)),
        ], kind: .other, today: today)
        #expect(beforeBirth.fields.map(\.key) == [.birthDate])

        // A permanent card issued 18 years ago is possible: kept, marked "Verifică".
        let old = CaptureConsistency.resolve([field(.issueDate, day(2008, 6, 1))], kind: .identityCard, today: today)
        #expect(old.fields.count == 1)
        #expect(old.fields.first?.needsCheck == true)

        let recent = CaptureConsistency.resolve([field(.issueDate, day(2021, 6, 1))], kind: .identityCard, today: today)
        #expect(recent.fields.first?.needsCheck == false)
    }

    @Test("A birth date is a living person's")
    func birthWindow() {
        #expect(CaptureConsistency.resolve([field(.birthDate, day(1901, 1, 1))], kind: .passport, today: today).fields.isEmpty)
        #expect(CaptureConsistency.resolve([field(.birthDate, day(2027, 1, 1))], kind: .passport, today: today).fields.isEmpty)
        #expect(CaptureConsistency.resolve([field(.birthDate, day(1952, 3, 1))], kind: .passport, today: today).fields.count == 1)
    }

    // MARK: Through the readers

    @Test("Printed passport: a misread 1906 expiry is never shown, and the zone's checked expiry stands")
    func printedPassportMisread() async throws {
        let printed = """
        PAȘAPORT / PASSPORT
        Nume / Surname
        EXEMPLU
        Data nașterii / Date of birth
        20.05.1990
        Data expirării / Date of expiry
        12.03.1906
        """
        let engine = CaptureEngine(analyzer: CaptureAnalyzer(), recognizer: CaptureEngineTests.FixedRecognizer(text: printed),
                                   normalizer: nil, onDeviceModel: nil, cloudModel: nil, store: nil)
        let alone = try await engine.capture(CaptureRequest(.text(printed), options: CaptureOptions(referenceDate: now)))
        #expect(alone.kind == .passport)
        #expect(alone.field(.expiryDate) == nil)
        #expect(alone.reminder == nil)

        let withZone = printed + "\n" + MRZFixtures.passport(expiry: "310412")
        let both = try await engine.capture(CaptureRequest(.text(withZone), options: CaptureOptions(referenceDate: now)))
        #expect(both.field(.expiryDate)?.value.day == day(2031, 4, 12))
        #expect(both.field(.expiryDate)?.tier == .deterministic)
    }

    @Test("The zone reads two-digit years through the windows")
    func zoneCenturies() throws {
        let expired = try #require(MRZParser.parse(text: MRZFixtures.passport(birth: "520301", expiry: "060312"), referenceDate: now))
        #expect(expired.allChecksValid)
        #expect(expired.birthDate == day(1952, 3, 1))
        #expect(expired.expiryDate == day(2006, 3, 12))

        let child = try #require(MRZParser.parse(text: MRZFixtures.passport(birth: "200101", expiry: "300101"), referenceDate: now))
        #expect(child.birthDate == day(2020, 1, 1))
        #expect(child.expiryDate == day(2030, 1, 1))
    }

    @Test("Bilingual passport dates with a short year")
    func bilingualMonths() {
        let window = CaptureConsistency.window(for: .expiryDate, kind: .passport, today: today)
        let found = RomanianFieldExtractor.dates(inLine: "12 iun/jun 31", index: 0, window: window).map(\.day)
        #expect(found == [day(2031, 6, 12)])
        #expect(RomanianFieldExtractor.dates(inLine: "07 mai/may 2029", index: 0).map(\.day) == [day(2029, 5, 7)])
    }

    @Test("The older card's validity range reads each year in its own window")
    func olderCardRange() {
        let text = """
        ROMANIA
        CARTE DE IDENTITATE
        SERIA XT NR 123456
        Nume/Nom/Last name
        EXEMPLU
        Valabilitate/Validite/Validity
        12.03.18-31.12.28
        """
        let analysis = CaptureAnalyzer().analyze(text: text, referenceDate: now)
        #expect(analysis.kind == .identityCard)
        #expect(analysis.fields.first { $0.key == .issueDate }?.value.day == day(2018, 3, 12))
        #expect(analysis.fields.first { $0.key == .expiryDate }?.value.day == day(2028, 12, 31))
    }
}

/// Synthetic machine-readable zones with placeholder data (the fictional "UTO" state from
/// ICAO Doc 9303, the placeholder CNP 1800101990006), check digits computed.
enum MRZFixtures {

    static func digit(_ field: String) -> String {
        String(MRZParser.checkDigit(for: field) ?? 0)
    }

    /// A TD3 passport zone. Fields are given as printed; check digits are computed.
    static func passport(
        surname: String = "EXEMPLU", given: String = "ANA",
        number: String = "X04512378", birth: String = "900520", sex: String = "F",
        expiry: String = "310412", optional: String = "1800101990006<"
    ) -> String {
        let names = "\(surname)<<\(given)"
        let line1 = ("P<UTO" + names).padding(toLength: 44, withPad: "<", startingAt: 0)
        let body = number + digit(number) + "UTO" + birth + digit(birth) + sex + expiry + digit(expiry) + optional + digit(optional)
        let composite = number + digit(number) + birth + digit(birth) + expiry + digit(expiry) + optional + digit(optional)
        let line2 = body + digit(composite)
        return line1 + "\n" + line2
    }

    /// A TD1 identity card zone (the back of the card).
    static func identityCard(number: String = "XT1234567", birth: String = "900520", expiry: String = "310412") -> String {
        let line1 = ("I<UTO" + number + digit(number)).padding(toLength: 30, withPad: "<", startingAt: 0)
        let upper = String(line1.dropFirst(5))
        let lowerOptional = String(repeating: "<", count: 11)
        let line2Start = birth + digit(birth) + "F" + expiry + digit(expiry) + "UTO" + lowerOptional
        let composite = upper + birth + digit(birth) + expiry + digit(expiry) + lowerOptional
        let line2 = line2Start + digit(composite)
        let line3 = "EXEMPLU<<ANA".padding(toLength: 30, withPad: "<", startingAt: 0)
        return [line1, line2, line3].joined(separator: "\n")
    }

    /// One character of a line swapped, as recognition might.
    static func replacing(_ text: String, line: Int, at index: Int, with character: Character) -> String {
        var lines = text.components(separatedBy: "\n")
        var characters = Array(lines[line])
        characters[index] = character
        lines[line] = String(characters)
        return lines.joined(separator: "\n")
    }
}
