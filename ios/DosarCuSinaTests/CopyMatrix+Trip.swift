import Foundation
import Testing
@testable import DosarCuSina

/// „Pleci din țară” in `docs/COPY_MATRIX.md`: what the trip check asks of each traveller, by
/// the group their citizenship falls in (`Citizenship.Group`) and the region, from the rules
/// (`TravelRules`) and their words (`TravelWording`), then what each need says once a document
/// is in the binder.
extension CopyMatrixTests {
    static var tripSampleDay: CalendarDay { CalendarDay("2027-05-03") }
    /// The day the sample is read on: before the sample day, so its words speak of a day to come.
    static var tripSampleToday: CalendarDay { CalendarDay("2027-04-01") }
    /// A day already passed by then, for the words of a document that has expired.
    static var tripSamplePast: CalendarDay { CalendarDay("2027-03-01") }

    static func tripRow(_ requirements: [TravelRequirement], region: TripPlan.Region, asksCitizenship: Bool = false) -> String {
        var words = requirements.map { "\(TravelWording.title(of: $0)) — \(TravelWording.missing($0))" }
        if asksCitizenship { words.insert("\(TravelWording.citizenshipTitle) — \(TravelWording.citizenshipAsked)", at: 0) }
        if TravelRules.checksHealthCard(in: region) { words.append(DocumentType.label(for: DocumentType.euHealthCard) ?? "") }
        if TravelRules.remindsOfVisa(in: region) { words.append("\(TravelWording.visaTitle) — \(TravelWording.visaDetail)") }
        return words.joined(separator: " · ")
    }

    /// What one group is asked in each region, row by row.
    static func tripRows(_ group: Citizenship.Group) -> [(String, String)] {
        TripPlan.Region.allCases.map { region in
            ("\(region.title) („\(region.summary)”)", tripRow(TravelRules.requirements(for: group, in: region), region: region, asksCitizenship: group == .unknown))
        }
    }

    /// The citizenships whose identity card a region's countries take, beyond their group's rule.
    static var tripIdentityCardRows: [(String, String)] {
        TripPlan.Region.allCases.compactMap { region in
            guard let cards = TravelRules.identityCards[region] else { return nil }
            let citizens = cards.citizens.sorted().compactMap { Citizenship.label(for: Citizenship.key($0)) }.joined(separator: ", ")
            return ("\(region.title) · \(citizens)", tripRow([cards.requirement], region: region))
        }
    }

    /// What each need says about a document of each type it takes: valid through the trip,
    /// ending before it, or already expired.
    static var tripNeedRows: [(String, String)] {
        let day = tripSampleDay
        return TravelRules.allRequirements.flatMap { requirement in
            requirement.accepted.map { type in
                let extra = (requirement.countsTravelCutoff ? " (travel cut-off)" : "")
                    + (requirement.monthsValidAfterReturn > 0 ? " (\(requirement.monthsValidAfterReturn) months after return)" : "")
                let name = "`\(requirement.need.rawValue)`\(extra) · \(DocumentType.label(for: type) ?? type)"
                var words = [TravelWording.valid(requirement, type: type, until: day, instead: false)]
                if type != requirement.accepted.first { words.append(TravelWording.valid(requirement, type: type, until: day, instead: true)) }
                words.append(TravelWording.ends(requirement, type: type, expiry: day, goodUntil: day, today: tripSampleToday))
                words.append(TravelWording.ends(requirement, type: type, expiry: tripSamplePast, goodUntil: tripSamplePast, today: tripSampleToday))
                return (name, words.joined(separator: " / "))
            }
        } + [("A document with no expiry", TravelWording.undated),
             ("The simple identity card (CIS)", TravelWording.notATravelDocument),
             ("Documents filed under no one, no citizenship", "\(TravelWording.citizenshipTitle) — \(TravelWording.citizenshipOfUnfiled)")]
    }

    /// "## Pleci din țară" of `docs/COPY_MATRIX.md`.
    static func tripSection() -> String {
        var out = "## Pleci din țară\n\nWhat the trip check asks of each traveller, by the group their citizenship falls in "
            + "(`Citizenship.Group`: read from the person, else from their documents; never assumed; a person with several travels on the most favourable) "
            + "and where they go, from `TravelRules` and `TravelWording`. Sample day: \(DosarFormat.longDay(tripSampleDay)).\n"
        for group in Citizenship.Group.allCases {
            out += "\n### `\(group.rawValue)`\n\n" + table(tripRows(group)) + "\n"
        }
        out += "\n### Where an identity card is taken\n\n" + table(tripIdentityCardRows) + "\n"
        out += "\n### What each need says\n\n" + table(tripNeedRows) + "\n"
        return out
    }

    @Test("Every need's words name the document they are about, and no two needs read alike")
    func tripWordsFitTheirNeed() {
        for requirement in TravelRules.allRequirements {
            #expect(!TravelWording.title(of: requirement).isEmpty)
            #expect(!TravelWording.missing(requirement).isEmpty)
        }
        let missing = TravelRules.allRequirements.map(TravelWording.missing)
        #expect(Set(missing).count == missing.count)
    }

    @Test("A document that has expired is said as expired, for every need and type")
    func tripExpiredWordsArePast() {
        for requirement in TravelRules.allRequirements {
            for type in requirement.accepted {
                let words = TravelWording.ends(requirement, type: type, expiry: Self.tripSamplePast, goodUntil: Self.tripSamplePast, today: Self.tripSampleToday)
                #expect(words.hasPrefix("A expirat pe"), "\(requirement.need) \(type): \(words)")
            }
        }
    }
}
