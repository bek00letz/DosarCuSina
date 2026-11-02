import Foundation

/// Defines a pre-configured asset template with recommended telemetry counters,
/// recurring maintenance cadences, and custom dynamic attributes.
public struct StarterTemplate: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let category: AssetCategory
    public let iconName: String
    public let accentColorHex: String
    public let primaryMetric: String
    public let metricUnit: String?
    public let initialMetricValue: Double?
    public let suggestedEvents: [TemplateEvent]
    public let suggestedFields: [TemplateField]
    
    public init(
        id: String,
        title: String,
        subtitle: String,
        category: AssetCategory,
        iconName: String,
        accentColorHex: String,
        primaryMetric: String,
        metricUnit: String?,
        initialMetricValue: Double?,
        suggestedEvents: [TemplateEvent],
        suggestedFields: [TemplateField]
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.category = category
        self.iconName = iconName
        self.accentColorHex = accentColorHex
        self.primaryMetric = primaryMetric
        self.metricUnit = metricUnit
        self.initialMetricValue = initialMetricValue
        self.suggestedEvents = suggestedEvents
        self.suggestedFields = suggestedFields
    }
    
    public var metricBadgeTitle: String {
        switch primaryMetric {
        case "kilometers": return "Contor km"
        case "hours": return "Contor ore"
        case "cycles": return "Contor cicluri"
        case "kilowatt_hours": return "Contor kWh"
        default: return "Calendaristic"
        }
    }
    
    public var metricBadgeIcon: String {
        switch primaryMetric {
        case "kilometers": return "gauge.with.dots.needle.bottom.50percent"
        case "hours": return "hourglass"
        case "cycles": return "arrow.triangle.2.circlepath"
        case "kilowatt_hours": return "bolt.fill"
        default: return "calendar"
        }
    }
}

public struct TemplateEvent: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    public let cadenceDays: Int?
    public let cadenceMetricValue: Double?
    public let metricUnit: String?
    public let initialDueOffsetDays: Int
    public let cost: Double?
    
    public init(
        id: UUID = UUID(),
        title: String,
        cadenceDays: Int? = nil,
        cadenceMetricValue: Double? = nil,
        metricUnit: String? = nil,
        initialDueOffsetDays: Int = 30,
        cost: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.cadenceDays = cadenceDays
        self.cadenceMetricValue = cadenceMetricValue
        self.metricUnit = metricUnit
        self.initialDueOffsetDays = initialDueOffsetDays
        self.cost = cost
    }
}

public struct TemplateField: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let key: String
    public let label: String
    public let fieldType: DynamicFieldType
    public let defaultString: String?
    public let defaultNumber: Double?
    
    public init(
        id: UUID = UUID(),
        key: String,
        label: String,
        fieldType: DynamicFieldType = .text,
        defaultString: String? = nil,
        defaultNumber: Double? = nil
    ) {
        self.id = id
        self.key = key
        self.label = label
        self.fieldType = fieldType
        self.defaultString = defaultString
        self.defaultNumber = defaultNumber
    }
    
    public var defaultValueDescription: String {
        if let s = defaultString, !s.isEmpty {
            return s
        }
        if let n = defaultNumber {
            return "\(n)"
        }
        return fieldType.displayTitle
    }
}

// MARK: - Pre-configured Starter Catalog
extension StarterTemplate {
    public static let allTemplates: [StarterTemplate] = [
        // 1. Bicicletă / E-Bike
        StarterTemplate(
            id: "bike",
            title: "Bicicletă / E-Bike",
            subtitle: "Mentenanță lanț, presiune roți, frâne și furcă",
            category: .custom,
            iconName: "bicycle",
            accentColorHex: "34C759",
            primaryMetric: "kilometers",
            metricUnit: "km",
            initialMetricValue: 0.0,
            suggestedEvents: [
                TemplateEvent(title: "Ungere și curățare lanț", cadenceDays: 14, cadenceMetricValue: 150, metricUnit: "km", initialDueOffsetDays: 14, cost: 35),
                TemplateEvent(title: "Verificare presiune cauciucuri", cadenceDays: 7, initialDueOffsetDays: 7, cost: 0),
                TemplateEvent(title: "Verificare uzură plăcuțe frână", cadenceMetricValue: 1000, metricUnit: "km", initialDueOffsetDays: 60, cost: 80),
                TemplateEvent(title: "Înlocuire lanț transmisie", cadenceMetricValue: 2000, metricUnit: "km", initialDueOffsetDays: 180, cost: 120),
                TemplateEvent(title: "Service suspensie / furcă", cadenceDays: 365, cadenceMetricValue: 100, metricUnit: "hours", initialDueOffsetDays: 180, cost: 250)
            ],
            suggestedFields: [
                TemplateField(key: "tip_bicicleta", label: "Tip Bicicletă", defaultString: "MTB / E-Bike"),
                TemplateField(key: "serie_cadru", label: "Serie Cadru", defaultString: ""),
                TemplateField(key: "marime_roti", label: "Mărime Roți", defaultString: "29 inch")
            ]
        ),
        
        // 2. Plante de Interior
        StarterTemplate(
            id: "plants",
            title: "Plante de Interior & Grădină",
            subtitle: "Program udare, fertilizare de sezon și schimbat pământ",
            category: .custom,
            iconName: "leaf.fill",
            accentColorHex: "00C7BE",
            primaryMetric: "calendar",
            metricUnit: nil,
            initialMetricValue: nil,
            suggestedEvents: [
                TemplateEvent(title: "Udare periodică", cadenceDays: 7, initialDueOffsetDays: 3, cost: 0),
                TemplateEvent(title: "Fertilizare de sezon (primăvară/vară)", cadenceDays: 30, initialDueOffsetDays: 14, cost: 25),
                TemplateEvent(title: "Schimbare substrat și ghiveci", cadenceDays: 730, initialDueOffsetDays: 180, cost: 45),
                TemplateEvent(title: "Curățare praf frunze & pulverizare", cadenceDays: 14, initialDueOffsetDays: 7, cost: 0)
            ],
            suggestedFields: [
                TemplateField(key: "specie_nume", label: "Specie / Nume Plantă", defaultString: "Monstera"),
                TemplateField(key: "nivel_lumina", label: "Nivel Lumină", defaultString: "Lumină indirectă")
            ]
        ),
        
        // 3. Proprietăți Închiriate
        StarterTemplate(
            id: "landlord",
            title: "Proprietăți Închiriate",
            subtitle: "Index contoare, încasare chirie, revizie centrală și contract ANAF",
            category: .home,
            iconName: "building.2.fill",
            accentColorHex: "5856D6",
            primaryMetric: "calendar",
            metricUnit: nil,
            initialMetricValue: nil,
            suggestedEvents: [
                TemplateEvent(title: "Scadență plată / încasare chirie", cadenceDays: 30, initialDueOffsetDays: 10, cost: 2200),
                TemplateEvent(title: "Transmitere index apometre & utilități", cadenceDays: 30, initialDueOffsetDays: 25, cost: 0),
                TemplateEvent(title: "Verificare Tehnică Centrală (VTP)", cadenceDays: 730, initialDueOffsetDays: 120, cost: 350),
                TemplateEvent(title: "Declarația Unică ANAF (Formular 212 - 25 Mai)", cadenceDays: 365, initialDueOffsetDays: 150, cost: 0),
                TemplateEvent(title: "Reînnoire înregistrare contract ANAF", cadenceDays: 365, initialDueOffsetDays: 240, cost: 0)
            ],
            suggestedFields: [
                TemplateField(key: "nume_chirias", label: "Nume Chiriaș", defaultString: ""),
                TemplateField(key: "numar_contract", label: "Număr Contract ANAF", defaultString: ""),
                TemplateField(key: "garantie", label: "Garanție Depusă (RON)", fieldType: .currency, defaultNumber: 4400.0)
            ]
        ),
        
        // 4. Panouri Fotovoltaice & Prosumator
        StarterTemplate(
            id: "solar",
            title: "Panouri Fotovoltaice & Prosumator",
            subtitle: "Producție solară kWh, injecție în rețea, curățare panouri și revizie invertor",
            category: .custom,
            iconName: "sun.max.fill",
            accentColorHex: "FF9500",
            primaryMetric: "kilowatt_hours",
            metricUnit: "kWh",
            initialMetricValue: 0.0,
            suggestedEvents: [
                TemplateEvent(title: "Verificare producție & raport lunar prosumator", cadenceDays: 30, initialDueOffsetDays: 30, cost: 0),
                TemplateEvent(title: "Curățare panouri fotovoltaice de praf / polen", cadenceDays: 180, initialDueOffsetDays: 90, cost: 250),
                TemplateEvent(title: "Revizie tehnică invertor & tablou PRAM", cadenceDays: 730, initialDueOffsetDays: 365, cost: 400)
            ],
            suggestedFields: [
                TemplateField(key: "putere_instalata", label: "Putere Instalată (kWp)", fieldType: .number, defaultNumber: 6.0),
                TemplateField(key: "model_invertor", label: "Model Invertor", defaultString: "Huawei SUN2000"),
                TemplateField(key: "serie_invertor", label: "Serie Invertor S/N", defaultString: ""),
                TemplateField(key: "numar_atr", label: "Număr Aviz Tehnic Racordare (ATR)", defaultString: "")
            ]
        ),
        
        // 5. Espressor de Cafea
        StarterTemplate(
            id: "espresso",
            title: "Espressor de Cafea",
            subtitle: "Decalcifiere, schimbat filtru apă și curățare grup",
            category: .custom,
            iconName: "cup.and.saucer.fill",
            accentColorHex: "A2845E",
            primaryMetric: "cycles",
            metricUnit: "cicluri",
            initialMetricValue: 0.0,
            suggestedEvents: [
                TemplateEvent(title: "Curățare chimică grup (Cafiza)", cadenceDays: 14, cadenceMetricValue: 100, metricUnit: "extracții", initialDueOffsetDays: 7, cost: 30),
                TemplateEvent(title: "Decalcifiere completă boiler", cadenceDays: 60, cadenceMetricValue: 300, metricUnit: "extracții", initialDueOffsetDays: 30, cost: 40),
                TemplateEvent(title: "Înlocuire filtru apă / rășină dedurizatoare", cadenceDays: 60, initialDueOffsetDays: 45, cost: 65),
                TemplateEvent(title: "Curățare duză spumare lapte", cadenceDays: 7, initialDueOffsetDays: 2, cost: 0)
            ],
            suggestedFields: [
                TemplateField(key: "model_aparat", label: "Model Espressor", defaultString: ""),
                TemplateField(key: "duritate_apa", label: "Duritate Apă (dH)", fieldType: .number, defaultNumber: 7.0),
                TemplateField(key: "diametru_portfiltru", label: "Portfiltru", defaultString: "58mm")
            ]
        ),
        
        // 6. Ambarcațiuni / Bărci
        StarterTemplate(
            id: "boat",
            title: "Ambarcațiuni / Bărci",
            subtitle: "Revizie motor barcă, antivegetativă și verificare veste salvare",
            category: .custom,
            iconName: "sailboat.fill",
            accentColorHex: "32ADE6",
            primaryMetric: "hours",
            metricUnit: "ore",
            initialMetricValue: 0.0,
            suggestedEvents: [
                TemplateEvent(title: "Revizie motor barcă (Ulei & Filtre)", cadenceDays: 365, cadenceMetricValue: 100, metricUnit: "ore", initialDueOffsetDays: 90, cost: 850),
                TemplateEvent(title: "Vopsea antivegetativă (Antifouling)", cadenceDays: 365, initialDueOffsetDays: 120, cost: 1200),
                TemplateEvent(title: "Verificare veste salvare & siguranță", cadenceDays: 180, initialDueOffsetDays: 60, cost: 0),
                TemplateEvent(title: "Verificare anod sacrificiu (zinc)", cadenceDays: 180, initialDueOffsetDays: 90, cost: 150)
            ],
            suggestedFields: [
                TemplateField(key: "nr_inmatriculare", label: "Număr Pavilion / Înmatriculare", defaultString: ""),
                TemplateField(key: "putere_motor", label: "Putere Motor (CP)", fieldType: .number, defaultNumber: 115.0),
                TemplateField(key: "port_acostare", label: "Port de Ambarcare", defaultString: "")
            ]
        )
    ]
}
