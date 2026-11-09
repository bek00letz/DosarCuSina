import Foundation

/// The providers whose bills the phone knows by name (gas, electricity, internet, TV and
/// phone), as data: the words that name each on its documents, and the name the binder
/// keeps. A new provider is a new row, never new reading code.
///
/// A name printed on the page is what lets `UtilityInvoiceParser` claim a bill (with the
/// classifier's agreement, or when it isn't sure); everything else on the bill is read the
/// same way for every provider (`BillReader`, `ContractReader`).
enum UtilityProviders {

    /// One way a provider is named: a word or phrase, alone or only beside one of
    /// `alongside` somewhere on the page ("DIGI" with "România", never "digital").
    struct Signature: Sendable {
        let words: String
        let alongside: [String]

        init(_ words: String, alongside: [String] = []) {
            self.words = words
            self.alongside = alongside
        }
    }

    struct Provider: Sendable, Hashable {
        /// The name the binder keeps for the provider ("ENGIE Romania").
        let name: String
        let signatures: [Signature]

        static func == (lhs: Provider, rhs: Provider) -> Bool { lhs.name == rhs.name }
        func hash(into hasher: inout Hasher) { hasher.combine(name) }
    }

    /// Known providers, in the order they are tried: a page naming two (a Hidroelectrica
    /// bill that mentions E.ON as the network operator) is the first one's.
    static let all: [Provider] = [
        Provider(name: "Hidroelectrica", signatures: [Signature("hidroelectrica"), Signature("speeh")]),
        Provider(name: "Digi (RCS & RDS)", signatures: [
            Signature("rcs & rds"),
            Signature("digi", alongside: ["romania", "telecom", "factura", "servicii"]),
        ]),
        Provider(name: "PPC / Enel", signatures: [Signature("ppc energie"), Signature("ppc"), Signature("enel energie"), Signature("enel")]),
        Provider(name: "ENGIE Romania", signatures: [Signature("engie"), Signature("gdf suez")]),
        Provider(name: "E.ON Energie", signatures: [Signature("e.on"), Signature("eon energie"), Signature("eon")]),
        Provider(name: "Vodafone Romania", signatures: [Signature("vodafone")]),
        Provider(name: "Orange Romania", signatures: [Signature("orange")]),
    ]

    /// The known provider a page names, if any. Names match as whole words in folded text,
    /// so "DIGI" isn't in "digital" and "EON" isn't in "Leonte".
    static func named(in text: CaptureText) -> Provider? {
        named(inFolded: text.joinedFolded)
    }

    static func named(inFolded folded: String) -> Provider? {
        func has(_ words: String) -> Bool { CaptureText.containsWord(words, inFolded: folded, as: .word) }
        return all.first { provider in
            provider.signatures.contains { signature in
                has(signature.words) && (signature.alongside.isEmpty || signature.alongside.contains(where: has))
            }
        }
    }
}
