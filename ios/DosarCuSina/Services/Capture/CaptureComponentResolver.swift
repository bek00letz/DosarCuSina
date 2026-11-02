import Foundation

/// Maps a line-item description ("Plăcuțe frână față Bosch") to a normalized component key.
///
/// The maintenance log is keyed by component, so "when did I last change the brake pads"
/// works no matter how each garage words its invoice. Core's component catalog is the
/// source of truth for keys; it conforms to this protocol and replaces
/// ``KeywordComponentResolver`` when the two branches meet.
public protocol CaptureComponentResolving: Sendable {
    func componentKey(for description: String) -> String?
}

/// A keyword-based resolver for common car and home components, used until Core's catalog is wired in.
public struct KeywordComponentResolver: CaptureComponentResolving {

    /// Rules are checked in order, so specific ones (front pads) come before general ones (pads).
    /// Every keyword list must all appear in the folded description.
    static let rules: [(key: String, all: [[String]])] = [
        ("brakePadsFront", [["placut", "pastil", "brake pad"], ["fata", "front"]]),
        ("brakePadsRear", [["placut", "pastil", "brake pad"], ["spate", "rear"]]),
        ("brakePads", [["placut", "pastil", "brake pad"]]),
        ("brakeDiscsFront", [["disc"], ["fran", "brake"], ["fata", "front"]]),
        ("brakeDiscsRear", [["disc"], ["fran", "brake"], ["spate", "rear"]]),
        ("brakeDiscs", [["disc"], ["fran", "brake"]]),
        ("brakeFluid", [["lichid", "fluid"], ["fran", "brake", "dot 4", "dot4"]]),
        ("oilFilter", [["filtru", "filter"], ["ulei", "oil"]]),
        ("airFilter", [["filtru", "filter"], ["aer", "air"]]),
        ("cabinFilter", [["filtru", "filter"], ["polen", "habitaclu", "cabin"]]),
        ("fuelFilter", [["filtru", "filter"], ["combustibil", "motorina", "benzina", "fuel"]]),
        ("gearboxOil", [["ulei", "oil"], ["cutie", "gearbox", "transmisie"]]),
        ("engineOil", [["ulei", "oil"]]),
        ("timingBelt", [["distributie", "timing"]]),
        ("auxiliaryBelt", [["curea"], ["accesorii", "alternator", "transmisie"]]),
        ("clutch", [["ambreiaj", "clutch", "volanta", "volant masa dubla"]]),
        ("sparkPlugs", [["bujii", "bujie", "spark"]]),
        ("tapMixer", [["robinet", "baterie sanitara", "baterie lavoar", "baterie dus", "baterie bucatarie"]]),
        ("battery", [["acumulator", "baterie", "battery"]]),
        ("tyres", [["anvelop", "cauciuc", "tyre", "tire"]]),
        ("wheelAlignment", [["geometrie", "aliniere", "alignment"]]),
        ("wheelBalancing", [["echilibrare", "balancing"]]),
        ("shockAbsorbers", [["amortizor", "shock"]]),
        ("coolant", [["antigel", "lichid racire", "coolant"]]),
        ("acService", [["clima", "freon", "aer conditionat", "a/c"]]),
        ("wipers", [["stergator", "lamel", "wiper"]]),
        ("boilerService", [["centrala", "boiler"], ["revizie", "verificare", "vtp", "service", "curatare"]]),
        ("waterHeater", [["boiler", "incalzitor apa"]]),
        ("gasDetector", [["detector"], ["gaz", "gas"]]),
        ("cookerHood", [["hota"]]),
        ("airConditionerFilters", [["aer conditionat", "split", "climatizare"], ["filtr", "igienizare", "curatare"]]),
        ("labour", [["manopera", "labour", "labor", "ore lucrate"]]),
    ]

    public init() {}

    public func componentKey(for description: String) -> String? {
        let folded = CaptureText.fold(description)
        return Self.rules.first { rule in
            rule.all.allSatisfy { alternatives in alternatives.contains { folded.contains($0) } }
        }?.key
    }
}
