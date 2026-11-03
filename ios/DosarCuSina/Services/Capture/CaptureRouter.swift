import Foundation

/// Turns a classified capture into suggestions (where it could go) and the deadline it
/// sets, all read from the kind's profile (`CaptureKindProfile`). Template, blueprint and
/// trade names are the binder's own: `vehicle`, `vehicle.rca`, `mechanic`. How early a
/// deadline reminds is never decided here: it is the blueprint's.
public enum CaptureRouter {

    public struct Routing: Sendable, Hashable {
        public let suggestions: [CaptureSuggestion]
        public let reminder: CaptureReminderHint?
    }

    public static func route(kind: CaptureDocumentKind, kindConfidence: Double, fields: [CaptureField]) -> Routing {
        let profile = kind.profile
        let lookup = Dictionary(fields.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        func text(_ key: CaptureFieldKey) -> String? { lookup[key]?.value.text }
        func hints(_ keys: [CaptureFieldKey]) -> [CaptureAssetHint] {
            keys.compactMap { key in text(key).map { CaptureAssetHint(key: key, value: $0) } }
        }
        let confidence = kindConfidence
        let vehicleHints = hints([.licensePlate, .vin])
        let cover = profile.cover(read: text(.coverageType), hasVehicle: !vehicleHints.isEmpty)
        let deadline = profile.deadline(cover: cover)
        let templateKey = profile.filedTemplateKey(cover: cover)
        // A policy finds its car by the plate only when it covers a car.
        let assetHints = profile.readsCover && templateKey != BuiltInTemplates.Key.vehicle ? [] : hints(profile.identifierKeys)

        var suggestions: [CaptureSuggestion] = []
        func suggest(_ destination: CaptureSuggestion.Destination, _ share: Double = 1, hints: [CaptureAssetHint]? = nil) {
            suggestions.append(CaptureSuggestion(destination: destination, assetHints: hints ?? assetHints, confidence: confidence * share))
        }
        let obligation = deadline.map { CaptureSuggestion.Destination.obligation(blueprintKey: $0.blueprintKey, templateKey: $0.templateKey) }

        switch profile.filing {
        case .newSection:
            // A receipt makes a product only when it names one; otherwise it is only kept.
            let namesProduct = text(.productName) != nil || text(.serialNumber) != nil || lookup[.warrantyMonths] != nil
            if kind == .fiscalReceipt, !namesProduct {
                suggest(.attachOnly, 0.6, hints: [])
            } else if let templateKey {
                suggest(.newAsset(templateKey: templateKey))
                if let obligation, kind.isIdentityDocument { suggest(obligation) }
            }
        case .intoSection:
            if let obligation { suggest(obligation) }
            if profile.logsHistory { suggest(.historyEntry(templateKey: templateKey), obligation == nil ? 1 : 0.7) }
            if obligation == nil, !profile.logsHistory, let templateKey { suggest(.historyEntry(templateKey: templateKey)) }
        case .subscription:
            // A bill belongs to its ongoing contract: logged in the subscription's history,
            // with its own due date to pay by. A contract sets the end of its minimum period.
            if profile.logsHistory { suggest(.historyEntry(templateKey: templateKey)) }
            if let obligation { suggest(obligation, profile.logsHistory ? 0.8 : 1) }
        case .keepOnly:
            suggestions.append(CaptureSuggestion(destination: .attachOnly, confidence: 0.5))
        }

        if let provider = text(.provider), !kind.isIdentityDocument {
            suggestions.append(CaptureSuggestion(destination: .provider(name: provider, trade: profile.trade?.rawValue), confidence: confidence * 0.9))
        }
        let day = profile.deadlineField.flatMap { lookup[$0]?.value.day }
        let reminder = both(deadline, day).map { deadline, day in
            CaptureReminderHint(day: day, blueprintKey: deadline.blueprintKey, templateKey: deadline.templateKey)
        }
        return Routing(suggestions: suggestions, reminder: reminder)
    }

    /// The codes that find a bill's or a contract's subscription, most specific first.
    static var subscriptionHintKeys: [CaptureFieldKey] { CaptureKindProfile.subscriptionCodes }
}

/// Both values, when both are there.
private func both<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
    guard let a, let b else { return nil }
    return (a, b)
}
