import Foundation
import MonitorCore

struct QuotaWindowSeriesKey: Hashable {
    let accountScopeID: String?
    let accountScopeState: String
    let scope: String
    let scopeIdentifier: String?
    let limitIdentity: String?
    let slot: String
    let windowMinutes: Int64?

    var stableID: String {
        [accountScopeID ?? "unknown", accountScopeState, scope, scopeIdentifier ?? "unknown",
         limitIdentity ?? "unknown", slot, windowMinutes.map(String.init) ?? "unknown"].joined(separator: "|")
    }
}

struct QuotaWindowCandidate {
    let snapshot: UsageLimitSnapshotObservation
    let window: UsageLimitWindowObservation

    var seriesKey: QuotaWindowSeriesKey {
        let limitIdentity = snapshot.limitID.flatMap { $0.isEmpty ? nil : "id:\($0)" }
            ?? snapshot.limitName.flatMap { $0.isEmpty ? nil : "name:\($0)" }
        return QuotaWindowSeriesKey(
            accountScopeID: snapshot.accountScopeID, accountScopeState: snapshot.accountScopeState.rawValue,
            scope: snapshot.scope.rawValue, scopeIdentifier: snapshot.scopeIdentifier,
            limitIdentity: limitIdentity, slot: window.slot.rawValue, windowMinutes: window.windowMinutes
        )
    }
}
