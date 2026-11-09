import Foundation
import SwiftData

/// Finding categories by what they do (`CategoryBehavior`), not by their key, so code
/// never asks "is this the built-in X" and a custom category can take a built-in's part.
extension TemplateStore {
    /// The category that plays `role`: the household's members, its documents, its
    /// subscriptions. A built-in comes first when a custom one plays the same part.
    public func template(withRole role: CategoryBehavior.Role) throws -> CategoryTemplate? {
        try all().filter { $0.behavior.role == role }.sorted { $0.isBuiltIn && !$1.isBuiltIn }.first
    }

    /// Each category's behaviour by key, for deciding many sections at once.
    public func behaviorsByKey() throws -> [String: CategoryBehavior] {
        try templatesByKey().mapValues(\.behavior)
    }

    /// The keys of every category that plays `role`, built-in or the person's own.
    public func keys(playing role: CategoryBehavior.Role) throws -> Set<String> {
        try all().keys(playing: role)
    }
}

extension Sequence where Element == CategoryTemplate {
    /// The keys of the categories that play `role`: the subscriptions, the people documents
    /// are filed under. What a screen's query asks instead of naming a built-in.
    public func keys(playing role: CategoryBehavior.Role) -> Set<String> {
        Set(filter { $0.behavior.role == role }.map(\.key))
    }
}

extension Dictionary where Key == String, Value == CategoryTemplate {
    /// The key of the category that plays `role`, a built-in first.
    public func key(withRole role: CategoryBehavior.Role) -> String? {
        values.filter { $0.behavior.role == role }.sorted { ($0.isBuiltIn ? 0 : 1, $0.homeOrder) < ($1.isBuiltIn ? 0 : 1, $1.homeOrder) }.first?.key
    }

    /// What the category `key` does; a category that isn't installed behaves as standard.
    public func behavior(of key: String) -> CategoryBehavior {
        self[key]?.behavior ?? .standard
    }

    /// Whether the category `key` plays `role`.
    public func plays(_ role: CategoryBehavior.Role, _ key: String) -> Bool {
        self[key]?.behavior.role == role
    }
}

extension Dictionary where Key == String, Value == CategoryBehavior {
    public func behavior(of key: String) -> CategoryBehavior {
        self[key] ?? .standard
    }

    /// Whether the category `key` plays `role`.
    public func plays(_ role: CategoryBehavior.Role, _ key: String) -> Bool {
        self[key]?.role == role
    }

    /// The key of a category that plays `role`.
    public func key(withRole role: CategoryBehavior.Role) -> String? {
        first { $0.value.role == role }?.key
    }
}
