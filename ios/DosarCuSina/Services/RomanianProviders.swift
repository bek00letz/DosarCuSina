import Foundation

public struct InsuranceProviderItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    
    public init(id: String, name: String) {
        self.id = id
        self.name = name
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
        InsuranceProviderItem(id: "paid", name: "PAID România (PAD Locuințe)"),
        InsuranceProviderItem(id: "other", name: "Alt Asigurător")
    ]
}
