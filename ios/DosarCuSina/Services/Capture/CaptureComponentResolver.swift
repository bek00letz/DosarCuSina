import Foundation

/// Maps a line-item description ("Plăcuțe frână față Bosch") to a component key.
///
/// The maintenance log is keyed by component, so "when did I last change the brake pads"
/// works no matter how each garage words its invoice.
public protocol CaptureComponentResolving: Sendable {
    func componentKey(for description: String) -> String?
}

/// Resolves descriptions against the templates' component catalogs, the one source
/// of truth for component keys (`brakes.padsFront`, `plumbing.taps`, …).
///
/// Pass the target template's components when the destination is known; the default
/// searches every built-in catalog, where the longest matching phrase wins
/// ("baterie lavoar" is the tap, "baterie" alone the car battery).
public struct CatalogComponentResolver: CaptureComponentResolving {
    let components: [ComponentDefinition]

    public init(components: [ComponentDefinition]) {
        self.components = components
    }

    public init() {
        self.init(components: BuiltInComponents.vehicle + BuiltInComponents.home + BuiltInComponents.pet
            + BuiltInComponents.bike + BuiltInComponents.espresso)
    }

    public func componentKey(for description: String) -> String? {
        ComponentCatalog.match(description, in: components)?.key
    }
}

/// Labour lines aren't parts, so they never get a component key: wherever a line item is
/// written (`HouseholdMutations.addItems`: a captured invoice's line, a row the person typed,
/// an import), one this rule calls labour is kept as the visit's labour cost, and nothing
/// that lists parts (Istoric's pocket, search's „Piese și lucrări”, when a part was last done)
/// counts it. Its words are capture's (`CaptureLexicon.labourWords`).
enum LabourLine {
    static func matches(_ description: String) -> Bool {
        let text = SearchText.normalize(description)
        return CaptureLexicon.labourWords.contains { SearchText.containsPhrase(text, $0) }
    }

    /// The names of what was done, without the labour: what a visit's title counts and names.
    /// A visit that lists only labour keeps it, so its title still says what it was.
    static func work(_ names: [String]) -> [String] {
        let work = names.filter { !matches($0) }
        return work.isEmpty ? names : work
    }
}
