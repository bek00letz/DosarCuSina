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
    
    public static let coverageTypes: [String] = [
        "RCA",
        "RCA cu Decontare Directă",
        "CASCO Complet",
        "CASCO Economic",
        "PAD Obligatoriu",
        "Facultativă Locuință",
        "Asigurare Sănătate / Accidente",
        "Asigurare Călătorie"
    ]
    
    public static let bonusMalusClasses: [String] = [
        "B8", "B7", "B6", "B5", "B4", "B3", "B2", "B1", "B0",
        "M1", "M2", "M3", "M4", "M5", "M6", "M7", "M8"
    ]
    
    public static func isInsuranceTitle(_ title: String) -> Bool {
        let lower = title.lowercased()
        return lower.contains("asigurare") ||
               lower.contains("rca") ||
               lower.contains("casco") ||
               lower.contains("pad") ||
               lower.contains("poliță") ||
               lower.contains("polita")
    }
}

public struct RomanianInsurers {
    public static let all: [String] = RomanianInsuranceCatalog.recommendedInsurers.map { $0.name }
    public static let coverageTypes: [String] = RomanianInsuranceCatalog.coverageTypes
    public static let bonusMalusClasses: [String] = [
        "B8 (-50%)", "B7 (-40%)", "B6 (-30%)", "B5 (-25%)",
        "B4 (-20%)", "B3 (-15%)", "B2 (-10%)", "B1 (-5%)",
        "B0 (0% Bază)",
        "M1 (+10%)", "M2 (+20%)", "M3 (+30%)", "M4 (+40%)",
        "M5 (+50%)", "M6 (+65%)", "M7 (+80%)", "M8 (+100%)"
    ]
}

public struct VehicleServiceCatalog {
    public static let commonComponents: [(name: String, category: String)] = [
        ("Plăcuțe frână față", "Frâne"),
        ("Plăcuțe frână spate", "Frâne"),
        ("Discuri frână față", "Frâne"),
        ("Discuri frână spate", "Frâne"),
        ("Lichid de frână (DOT 4/5.1)", "Frâne"),
        ("Schimb ulei motor", "Ulei & Filtre"),
        ("Filtru ulei", "Ulei & Filtre"),
        ("Filtru aer motor", "Ulei & Filtre"),
        ("Filtru polen / habitaclu", "Ulei & Filtre"),
        ("Filtru combustibil", "Ulei & Filtre"),
        ("Kit distribuție + pompă apă", "Motor & Transmisie"),
        ("Curea accesorii + rolă", "Motor & Transmisie"),
        ("Ulei cutie de viteze", "Motor & Transmisie"),
        ("Ambreiaj / volant", "Motor & Transmisie"),
        ("Bujii aprindere / incandescente", "Motor & Transmisie"),
        ("Baterie 12V (acumulator)", "Electric"),
        ("Alternator / electromotor", "Electric"),
        ("Amortizoare față / spate", "Suspensie & Direcție"),
        ("Bielete antiruliu", "Suspensie & Direcție"),
        ("Bucșe brațe suspensie", "Suspensie & Direcție"),
        ("Capete de bară / pivoți", "Suspensie & Direcție"),
        ("Geometrie roți (unghi de fugă)", "Suspensie & Direcție"),
        ("Schimb anvelope sezonier", "Anvelope"),
        ("Echilibrare roți", "Anvelope"),
        ("Igienizare climă + freon", "Climatizare"),
        ("Ștergătoare parbriz", "General")
    ]
}
