import Foundation

public struct InsuranceProviderItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    /// How its papers name it, folded and matched as whole words (`CaptureText.containsWord`):
    /// its short name, and its full one when that is how it prints itself.
    public let words: [String]

    public init(id: String, name: String, words: [String]? = nil) {
        self.id = id
        self.name = name
        self.words = words ?? [id]
    }
}

public struct RomanianInsuranceCatalog: Sendable {
    public static let recommendedInsurers: [InsuranceProviderItem] = [
        InsuranceProviderItem(id: "allianz", name: "Allianz-Țiriac Asigurări"),
        InsuranceProviderItem(id: "groupama", name: "Groupama Asigurări"),
        InsuranceProviderItem(id: "omniasig", name: "Omniasig VIG"),
        InsuranceProviderItem(id: "generali", name: "Generali România"),
        InsuranceProviderItem(id: "asirom", name: "Asirom VIG"),
        InsuranceProviderItem(id: "grawe", name: "Grawe România"),
        InsuranceProviderItem(id: "axeria", name: "Axeria IARD"),
        InsuranceProviderItem(id: "hellas", name: "Hellas Direct"),
        InsuranceProviderItem(id: "eurolife", name: "Eurolife FFH"),
        // A PAD prints the pool's full name; "PAID" alone is its short one.
        InsuranceProviderItem(id: "paid", name: "PAID România (PAD Locuințe)",
                              words: ["paid", "pool-ul de asigurare impotriva dezastrelor naturale", "pool ul de asigurare impotriva dezastrelor naturale",
                                      "poolul de asigurare impotriva dezastrelor naturale"]),
        InsuranceProviderItem(id: "other", name: "Alt Asigurător")
    ]
}
