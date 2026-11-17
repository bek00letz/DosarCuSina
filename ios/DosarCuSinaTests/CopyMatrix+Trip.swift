import Foundation
import Testing
@testable import DosarCuSina

/// „Pleci din țară” in `docs/COPY_MATRIX.md`: what the trip check asks of each traveller, by
/// the group their citizenship falls in (`Citizenship.Group`) and the region, from the rules
/// (`TravelRules`) and their words (`TravelWording`), then what each need says once a document
/// is in the binder.
extension CopyMatrixTests {
    static var tripSampleDay: CalendarDay { CalendarDay("2027-05-03") }

    /// What one group is asked in each region, row by row.
    static func tripRows(_ group: Citizenship.Group) -> [(String, String)] {
        TripPlan.Region.allCases.map { region in
            var words = TravelRules.requirements(for: group, in: region).map { "\(TravelWording.title(of: $0)) — \(TravelWording.missing($0))" }
            if group == .unknown { words.insert("\(TravelWording.citizenshipTitle) — \(TravelWording.citizenshipAsked)", at: 0) }
            if TravelRules.checksHealthCard(in: region) { words.append(DocumentType.label(for: DocumentType.euHealthCard) ?? "") }
            if TravelRules.remindsOfVisa(in: region) { words.append("\(TravelWording.visaTitle) — \(TravelWording.visaDetail)") }
            return ("\(region.title) („\(region.summary)”)", words.joined(separator: " · "))
        }
    }

    /// What each need says about a document of each type it takes: valid through the trip,
    /// or ending before it.
    static var tripNeedRows: [(String, String)] {
        let day = tripSampleDay
        let requirements = [TravelRules.identityOrPassport, TravelRules.passport, TravelRules.passportForTravel, TravelRules.residencePermit]
        return requirements.flatMap { requirement in
            requirement.accepted.map { type in
                let name = "`\(requirement.need.rawValue)`\(requirement.countsTravelCutoff ? " (travel cut-off)" : "") · \(DocumentType.label(for: type) ?? type)"
                var words = [TravelWording.valid(requirement, type: type, until: day, instead: false)]
                if type != requirement.accepted.first { words.append(TravelWording.valid(requirement, type: type, until: day, instead: true)) }
                words.append(TravelWording.ends(requirement, type: type, expiry: day, goodUntil: day))
                return (name, words.joined(separator: " / "))
            }
        } + [("A document with no expiry", TravelWording.undated),
             ("Documents filed under no one, no citizenship", "\(TravelWording.citizenshipTitle) — \(TravelWording.citizenshipOfUnfiled)")]
    }

    /// "## Pleci din țară" of `docs/COPY_MATRIX.md`.
    static func tripSection() -> String {
        var out = "## Pleci din țară\n\nWhat the trip check asks of each traveller, by the group their citizenship falls in "
            + "(`Citizenship.Group`: read from the person, else from their documents; never assumed) and where they go, "
            + "from `TravelRules` and `TravelWording`. Sample day: \(DosarFormat.longDay(tripSampleDay)).\n"
        for group in Citizenship.Group.allCases {
            out += "\n### `\(group.rawValue)`\n\n" + table(tripRows(group)) + "\n"
        }
        out += "\n### What each need says\n\n" + table(tripNeedRows) + "\n"
        return out
    }

    @Test("Every need's words name the document they are about, and no two needs read alike")
    func tripWordsFitTheirNeed() {
        for requirement in [TravelRules.identityOrPassport, TravelRules.passport, TravelRules.passportForTravel, TravelRules.residencePermit] {
            #expect(!TravelWording.title(of: requirement).isEmpty)
            #expect(!TravelWording.missing(requirement).isEmpty)
        }
        let missing = [TravelRules.identityOrPassport, TravelRules.passport, TravelRules.passportForTravel, TravelRules.residencePermit]
            .map(TravelWording.missing)
        #expect(Set(missing).count == missing.count)
    }
}
