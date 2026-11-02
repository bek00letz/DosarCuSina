import Foundation

/// Component catalogs for the built-in categories. Keys are stable and part of
/// archives; names and synonyms are what people write on bills.
public enum BuiltInComponents {
    private static func c(_ key: String, _ name: String.LocalizationValue, _ group: String.LocalizationValue, _ synonyms: [String] = []) -> ComponentDefinition {
        ComponentDefinition(key: key, name: String(localized: name), group: String(localized: group), synonyms: synonyms)
    }

    public static var vehicle: [ComponentDefinition] {
        [
            c("brakes.padsFront", "Plăcuțe frână față", "Frâne", ["placute fata", "placute de frana fata", "pastile frana fata", "pastile fata", "brake pads front"]),
            c("brakes.padsRear", "Plăcuțe frână spate", "Frâne", ["placute spate", "placute de frana spate", "pastile frana spate", "pastile spate", "brake pads rear"]),
            c("brakes.discsFront", "Discuri frână față", "Frâne", ["discuri fata", "discuri de frana fata", "disc frana fata", "disc fata"]),
            c("brakes.discsRear", "Discuri frână spate", "Frâne", ["discuri spate", "discuri de frana spate", "disc frana spate", "disc spate"]),
            c("brakes.fluid", "Lichid de frână", "Frâne", ["lichid frana", "dot 4", "brake fluid"]),
            c("engine.oil", "Ulei și filtru de ulei", "Motor", ["schimb ulei", "ulei motor", "filtru ulei", "oil change"]),
            c("filters.air", "Filtru de aer", "Filtre", ["filtru aer"]),
            c("filters.cabin", "Filtru de habitaclu", "Filtre", ["filtru polen", "filtru habitaclu", "filtru aer conditionat"]),
            c("filters.fuel", "Filtru de combustibil", "Filtre", ["filtru motorina", "filtru benzina", "filtru combustibil"]),
            c("engine.timing", "Distribuție (curea sau lanț)", "Motor", ["kit distributie", "curea distributie", "lant distributie", "distributie"]),
            c("engine.sparkPlugs", "Bujii", "Motor", ["bujie"]),
            c("engine.coolant", "Lichid de răcire", "Motor", ["antigel", "lichid racire"]),
            c("engine.auxiliaryBelt", "Curea de accesorii", "Motor", ["curea accesorii", "curea alternator", "curea transmisie"]),
            c("transmission.clutch", "Ambreiaj", "Transmisie", ["kit ambreiaj", "volanta", "volant masa dubla"]),
            c("transmission.gearboxOil", "Ulei cutie de viteze", "Transmisie", ["ulei cutie", "ulei transmisie"]),
            c("suspension.shockAbsorbers", "Amortizoare", "Suspensie", ["amortizor"]),
            c("tyres.summer", "Anvelope de vară", "Roți", ["cauciucuri vara", "anvelope vara"]),
            c("tyres.winter", "Anvelope de iarnă", "Roți", ["cauciucuri iarna", "anvelope iarna"]),
            c("tyres.alignment", "Geometrie roți", "Roți", ["geometrie", "aliniere"]),
            c("tyres.balancing", "Echilibrare roți", "Roți", ["echilibrare"]),
            c("electrical.battery", "Baterie", "Electric", ["acumulator"]),
            c("body.wipers", "Ștergătoare", "Caroserie", ["lamele stergator", "stergatoare"]),
            c("climate.acService", "Încărcare aer condiționat", "Climatizare", ["freon", "incarcare clima", "igienizare clima"]),
        ]
    }

    public static var home: [ComponentDefinition] {
        [
            c("heating.boiler", "Centrală termică", "Încălzire", ["centrala", "boiler gaz"]),
            c("heating.boilerService", "Revizie centrală", "Încălzire", ["revizie centrala", "verificare centrala", "vtp centrala", "curatare centrala"]),
            c("heating.radiators", "Calorifere", "Încălzire", ["calorifer", "radiator"]),
            c("plumbing.taps", "Robinete și baterii", "Instalații sanitare", ["robinet", "baterie baie", "baterie bucatarie", "baterie chiuveta", "baterie lavoar", "baterie dus", "baterie sanitara"]),
            c("plumbing.waterHeater", "Boiler electric", "Instalații sanitare", ["boiler electric"]),
            c("plumbing.toilet", "Rezervor și WC", "Instalații sanitare", ["rezervor wc", "vas wc"]),
            c("plumbing.waterFilter", "Filtru de apă", "Instalații sanitare", ["filtru apa", "dedurizator"]),
            c("gas.detector", "Detector de gaz", "Gaze", ["detector gaze", "senzor gaz"]),
            c("kitchen.hood", "Hotă", "Bucătărie", ["hota"]),
            c("kitchen.cooker", "Aragaz", "Bucătărie", ["plita", "cuptor"]),
            c("climate.acFilters", "Filtre aer condiționat", "Climatizare", ["igienizare aer conditionat", "filtre ac"]),
            c("electrical.panel", "Tablou electric", "Electric", ["tablou electric", "sigurante"]),
            c("windows.seals", "Garnituri geamuri", "Tâmplărie", ["garnituri", "reglaj geamuri"]),
        ]
    }

    public static var pet: [ComponentDefinition] {
        [
            c("vaccine.rabies", "Vaccin antirabic", "Vaccinuri", ["antirabic", "rabie"]),
            c("vaccine.core", "Vaccin anual", "Vaccinuri", ["polivalent", "dhppi", "tricat", "vaccin"]),
            c("parasites.internal", "Deparazitare internă", "Paraziți", ["milbemax", "drontal", "deparazitare interna"]),
            c("parasites.external", "Deparazitare externă", "Paraziți", ["bravecto", "pipeta", "zgarda", "deparazitare externa"]),
            c("care.dental", "Detartraj", "Îngrijire", ["detartraj", "curatare dentara"]),
            c("care.grooming", "Toaletaj", "Îngrijire", ["tuns", "toaletaj"]),
            c("medicine", "Tratament", "Tratamente", ["antibiotic", "tratament"]),
        ]
    }

    public static var bike: [ComponentDefinition] {
        [
            c("drivetrain.chain", "Lanț", "Transmisie", ["lant"]),
            c("drivetrain.cassette", "Casetă", "Transmisie", ["caseta", "pinioane"]),
            c("brakes.pads", "Plăcuțe de frână", "Frâne", ["placute"]),
            c("suspension.fork", "Service furcă", "Suspensie", ["furca"]),
            c("wheels.tyres", "Anvelope", "Roți", ["cauciucuri", "camera"]),
        ]
    }

    public static var espresso: [ComponentDefinition] {
        [
            c("maintenance.descale", "Decalcifiere", "Întreținere", ["decalcifiere"]),
            c("maintenance.gasket", "Garnitură grup", "Întreținere", ["garnitura"]),
            c("maintenance.waterFilter", "Filtru de apă", "Întreținere", ["filtru apa"]),
        ]
    }
}
