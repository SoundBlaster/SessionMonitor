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

enum QuotaAnomalyStatistics {
    static func format(_ value: Double) -> String { String(format: "%.2f", value) }

    static func median(_ values: [Double]) -> Double? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}

func quotaAnomalyReason(for state: UsageLimitSnapshotState) -> QuotaAnomalyReason? {
    switch state {
    case .observed: nil
    case .partial, .noWindowData: .incompleteCoverage
    case .unsupportedSchema: .unsupportedSnapshot
    }
}

struct QuotaResetBoundary {
    let outcome: QuotaAnomalyOutcome
    let reason: QuotaAnomalyReason?
    let detail: String
}

func quotaResetBoundary(
    sameObservationTime: Bool, previousReset: Date?, currentReset: Date?
) -> QuotaResetBoundary {
    if sameObservationTime {
        return QuotaResetBoundary(
            outcome: .unknown, reason: .ambiguousObservation,
            detail: "Conflicting reset identities share the same account, window and observation timestamp."
        )
    }
    guard previousReset != nil, currentReset != nil else {
        return QuotaResetBoundary(
            outcome: .unknown, reason: .missingReset,
            detail: "A reset boundary is ambiguous because one observation has no reset timestamp."
        )
    }
    return QuotaResetBoundary(
        outcome: .resetDiscontinuity, reason: nil,
        detail: "The reset timestamp changed; usage across this boundary was not compared."
    )
}
