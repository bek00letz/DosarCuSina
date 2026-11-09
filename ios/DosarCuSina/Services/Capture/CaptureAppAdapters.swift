import Foundation

// Readers that claim a family of documents for the capture pipeline. They live apart
// from the pure pipeline so the engine stays testable without them.

// MARK: - Utility invoices

/// Claims a bill from a provider the phone knows by name (`UtilityProviders`: Digi, PPC /
/// Enel, Hidroelectrica, E.ON, ENGIE, Orange, Vodafone), with the provider's name. Only
/// the claim and the name: the bill's values are read for every provider alike, by its
/// kind's label table (`BillReader`) and `ContractReader`.
///
/// The reader before this one, `RomanianUtilityParser`, is kept switched off in
/// `ios/Legacy/Services/OCR/` until this one is proven on real bills (docs/HANDOFF.md).
public struct UtilityInvoiceParser: CaptureSpecializedParser {

    public init() {}

    public func parse(_ text: CaptureText) -> CaptureAnalyzer.SpecializedParse? {
        guard let provider = UtilityProviders.named(in: text) else { return nil }
        let name = CaptureField(key: .provider, value: .text(provider.name), confidence: 0.95, sourceText: nil, tier: .deterministic)
        return CaptureAnalyzer.SpecializedParse(kind: .utilityInvoice, fields: [name])
    }
}
