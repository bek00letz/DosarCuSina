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

/// Labour lines aren't parts, so they never get a component key; the history
/// records them as the visit's labour cost instead.
enum LabourLine {
    static let phrases = ["manopera", "labour", "labor", "ore lucrate"]

    static func matches(_ description: String) -> Bool {
        let text = SearchText.normalize(description)
        return phrases.contains { SearchText.containsPhrase(text, $0) }
    }
}
