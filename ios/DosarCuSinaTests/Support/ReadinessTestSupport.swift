import Foundation
@testable import DosarCuSina

// Fixtures for the readiness checks: made-up people, documents and cars.

extension ReadinessAsset {
    /// A household member.
    static func member(_ name: String) -> ReadinessAsset {
        ReadinessAsset(name: name, templateKey: BuiltInTemplates.Key.member, role: .holder)
    }

    /// A personal document of `type` (`DocumentType`), expiring on `expires`, filed under `holder`.
    static func personalDocument(_ type: String, expires: String?, holder: ReadinessAsset? = nil, isSensitive: Bool = false) -> ReadinessAsset {
        var values = FieldValues()
        values[DocumentType.typeFieldKey] = .text(type)
        if let expires { values[DocumentFields.expiry] = .date(CalendarDay(expires)) }
        return ReadinessAsset(name: DocumentType.label(for: type) ?? type, templateKey: BuiltInTemplates.Key.documents,
                              role: .personalDocument, parentId: holder?.id, isSensitive: isSensitive, values: values)
    }

    /// A car with these deadlines, by blueprint key and due day.
    static func car(_ name: String = "VW Golf 2018", values: FieldValues = FieldValues(), dues: [String: String] = [:],
                    historyCount: Int = 0, documentKinds: [DocumentKind] = [], other: [ReadinessObligation] = []) -> ReadinessAsset {
        var obligations: [String: ReadinessObligation] = [:]
        for (key, due) in dues {
            let blueprint = BuiltInTemplates.vehicle.blueprints.first { $0.key == key }
            obligations[key] = ReadinessObligation(due: CalendarDay(due), title: blueprint?.title ?? key, kind: blueprint?.kind ?? .routine)
        }
        return ReadinessAsset(
            name: name, templateKey: BuiltInTemplates.Key.vehicle, values: values,
            obligations: obligations,
            otherObligations: other, historyCount: historyCount, documentKinds: documentKinds,
            facts: ReadinessFacts.of(BuiltInTemplates.vehicle)
        )
    }
}

extension TripPlan {
    /// A trip where everyone and everything in `assets` goes: every traveller, and the cars
    /// and pets when driving or with a pet.
    static func everyone(start: String, end: String, region: Region, driving: Bool = false, withPet: Bool = false, in assets: [ReadinessAsset]) -> TripPlan {
        let candidates = ReadinessEngine.tripCandidates(in: assets)
        return TripPlan(
            start: CalendarDay(start), end: CalendarDay(end), region: region,
            travellers: Set(candidates.travellers.map(\.traveller)),
            vehicles: driving ? Set(candidates.vehicles.map(\.id)) : [],
            pets: withPet ? Set(candidates.pets.map(\.id)) : []
        )
    }
}

extension Array where Element == ReadinessItem {
    subscript(id id: String) -> ReadinessItem? { first { $0.id == id } }
}
