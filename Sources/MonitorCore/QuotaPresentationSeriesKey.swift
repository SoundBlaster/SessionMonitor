import Foundation

/// Presentation identity is independent of reset intervals; anomaly series have a different contract.
public struct QuotaPresentationSeriesKey: Hashable, Sendable {
    let accountScopeID: String?
    let scope: UsageLimitScope
    let scopeIdentifier: String?
    let limitIdentity: LimitIdentity
    let slot: UsageLimitWindowSlot

    public init(snapshot: UsageLimitSnapshotObservation, window: UsageLimitWindowObservation) {
        accountScopeID = snapshot.accountScopeID
        scope = snapshot.scope
        scopeIdentifier = snapshot.scopeIdentifier
        slot = window.slot
        if let id = snapshot.limitID, !id.isEmpty {
            limitIdentity = .id(id)
        } else if let name = snapshot.limitName, !name.isEmpty {
            limitIdentity = .name(name)
        } else {
            limitIdentity = .anonymous
        }
    }

    /// Unambiguous SQLite key, with the same Unicode equivalence as Swift String/Hashable.
    public func storageKey() -> String {
        let kind: String
        let value: String?
        switch limitIdentity {
        case let .id(id): (kind, value) = ("id", id)
        case let .name(name): (kind, value) = ("name", name)
        case .anonymous: (kind, value) = ("anonymous", nil)
        }
        let parts = [accountScopeID, scope.rawValue, scopeIdentifier, kind, value, slot.rawValue]
        return parts.map { part in
            guard let value = part?.precomposedStringWithCanonicalMapping else { return "-" }
            return "\(value.utf8.count):\(value)"
        }.joined(separator: "|")
    }

    public var identifier: String {
        [accountScopeID ?? "unknown", scope.rawValue, scopeIdentifier ?? "unknown",
         limitIdentity.identifier, slot.rawValue]
            .joined(separator: "|")
    }

    enum LimitIdentity: Hashable, Sendable {
        case id(String)
        case name(String)
        case anonymous

        public var identifier: String {
            switch self {
            case let .id(value): value
            case let .name(value): "name:\(value)"
            case .anonymous: "unknown"
            }
        }
    }
}
