import Foundation
import Testing
@testable import DosarCuSina

/// „Vinzi mașina” and „Ai avut o daună” in `docs/COPY_MATRIX.md`: every check of each
/// situation's checklist, group by group, as `ReadinessEngine` words it, for a section with
/// nothing in the binder and for one with everything it reads. Each check names its outcome
/// (`ReadinessStatus.spokenTitle`), so an optional one reads „Opțional”, never as missing.
extension CopyMatrixTests {
    static var situationSampleToday: CalendarDay { CalendarDay("2027-05-03") }

    /// A car the binder knows nothing about, and one with every value, deadline and paper a
    /// sale or a claim reads.
    static func situationCars() -> (empty: ReadinessAsset, filled: ReadinessAsset) {
        let empty = ReadinessAsset(name: "VW Golf 2018", templateKey: BuiltInTemplates.Key.vehicle, facts: ReadinessFacts.of(BuiltInTemplates.vehicle))
        var values = FieldValues()
        values[VehicleFields.vin] = .text("WVWZZZ1KZAW000001")
        values[VehicleFields.civ] = .text("A000001")
        values[VehicleFields.policyNumber] = .text("RCA-000001")
        values[VehicleFields.claimsPhone] = .text("0210000001")
        var obligations: [String: ReadinessObligation] = [:]
        for key in [BuiltInBlueprints.vehicleITP, BuiltInBlueprints.vehicleRCA] {
            let blueprint = BuiltInTemplates.vehicle.blueprints.first { $0.key == key }
            obligations[key] = ReadinessObligation(due: CalendarDay("2028-01-10"), title: blueprint?.title ?? key, kind: blueprint?.kind ?? .routine)
        }
        let filled = ReadinessAsset(name: "VW Golf 2018", templateKey: BuiltInTemplates.Key.vehicle, values: values,
                                    obligations: obligations, historyCount: 3, documentKinds: [.invoice, .policy],
                                    facts: ReadinessFacts.of(BuiltInTemplates.vehicle))
        return (empty, filled)
    }

    /// A home the binder knows nothing about.
    static var situationHome: ReadinessAsset {
        ReadinessAsset(name: "Apartament", templateKey: BuiltInTemplates.Key.home, facts: ReadinessFacts.of(BuiltInTemplates.home))
    }

    /// One row per group: its title, then each check as „Title (outcome) — why”; something to
    /// bring or do, ticked off by hand, as „Title — what”.
    static func situationRows(_ checklist: ReadinessChecklist) -> [(String, String)] {
        checklist.groups.map { group in
            let words = group.items.map { item in
                item.status == .reminder
                    ? "\(item.title) — \(item.detail)"
                    : "\(item.title) (\(item.status.spokenTitle)) — \(item.detail)"
            }
            return (group.title, words.joined(separator: " · "))
        }
    }

    /// "## Vinzi mașina și Ai avut o daună" of `docs/COPY_MATRIX.md`.
    static func situationsSection() -> String {
        let today = situationSampleToday
        let cars = situationCars()
        let home = situationHome
        func checklist(_ scenario: ReadinessScenario, _ assets: [ReadinessAsset]) -> ReadinessChecklist {
            ReadinessEngine.checklist(scenario, assets: assets, today: today)
        }
        var out = "## \(ReadinessSituation.sale.title) și \(ReadinessSituation.claim.title)\n\n"
            + "Every check of each checklist, group by group, from `ReadinessEngine`, with its outcome in brackets "
            + "(an optional check, `ReadinessNeed.optional`, reads „\(ReadinessStatus.suggested.spokenTitle)”). "
            + "Sample day: \(DosarFormat.longDay(today)).\n"
        let shown: [(String, ReadinessChecklist)] = [
            ("\(ReadinessSituation.sale.title) · nothing in the binder", checklist(.sellingVehicle(assetId: cars.empty.id), [cars.empty])),
            ("\(ReadinessSituation.sale.title) · everything in the binder", checklist(.sellingVehicle(assetId: cars.filled.id), [cars.filled])),
            ("\(ReadinessSituation.claim.title) · a car, nothing in the binder", checklist(.insuranceClaim(assetId: cars.empty.id), [cars.empty])),
            ("\(ReadinessSituation.claim.title) · a car, everything in the binder", checklist(.insuranceClaim(assetId: cars.filled.id), [cars.filled])),
            ("\(ReadinessSituation.claim.title) · a home, nothing in the binder", checklist(.insuranceClaim(assetId: home.id), [home])),
        ]
        for (title, list) in shown {
            out += "\n### \(title)\n\n" + table(situationRows(list)) + "\n"
        }
        return out
    }

    @Test("Advice in a situation sends the person where to go, and calls 112 only for an emergency")
    func situationAdviceGoesToThePolice() {
        let words = Self.situationsSection()
        #expect(!words.contains("sună la poliție"), "Without agreement after a minor crash, the drivers go to the police station")
        #expect(!words.contains("112"), "A minor crash with no injuries is never a call to 112")
        #expect(words.contains("mergi la Poliție"))
    }
}
