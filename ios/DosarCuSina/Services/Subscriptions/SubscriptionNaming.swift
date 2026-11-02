import Foundation

/// What a subscription made from a bill or a contract is called: the service, then
/// who provides it ("Gaz – ENGIE Romania"), so two homes' gas contracts read the
/// same way and a household's several contracts with one provider stay apart.
public enum SubscriptionNaming {
    public static func name(provider: String?, service: String?) -> String {
        let provider = provider?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let service = ServiceKind.label(for: service).flatMap { $0 == ServiceKind.label(for: ServiceKind.other) ? nil : $0 }
        switch (service, provider) {
        case let (service?, provider?): return DocumentNaming.name(document: service, holder: provider)
        case let (nil, provider?): return provider
        case let (service?, nil): return service
        case (nil, nil): return String(localized: "Abonament")
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
