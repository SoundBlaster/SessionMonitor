import Foundation
import MonitorCore
import SpecificationCore

public struct QuotaPresentationConfiguration: Equatable, Sendable {
    public let freshnessThreshold: TimeInterval

    public init(freshnessThreshold: TimeInterval = 900) {
        self.freshnessThreshold = freshnessThreshold.isFinite && freshnessThreshold > 0
            ? freshnessThreshold : 900
    }
}

public struct QuotaPresentationContext: Sendable {
    public let report: UsageLimitSnapshotReport
    public let generatedAt: Date

    public init(report: UsageLimitSnapshotReport, generatedAt: Date? = nil) {
        self.report = report
        self.generatedAt = generatedAt ?? report.generatedAt
    }
}

private struct HasQuotaSnapshotsSpec: Specification {
    func isSatisfiedBy(_ candidate: QuotaPresentationContext) -> Bool {
        !candidate.report.snapshots.isEmpty
    }
}

private struct HasWindowObservationsSpec: Specification {
    func isSatisfiedBy(_ candidate: QuotaPresentationContext) -> Bool {
        candidate.report.snapshots.contains { !$0.windows.isEmpty }
    }
}

public struct QuotaPresentationDecision: DecisionSpec {
    public typealias Context = QuotaPresentationContext
    public typealias Result = QuotaPresentationReport

    public let configuration: QuotaPresentationConfiguration

    public init(configuration: QuotaPresentationConfiguration = .init()) {
        self.configuration = configuration
    }

    public func decide(_ context: Context) -> Result? {
        presentation(for: context)
    }

    public func presentation(for context: Context) -> Result {
        let hasSnapshots = HasQuotaSnapshotsSpec().isSatisfiedBy(context)
        let hasWindows = HasWindowObservationsSpec().isSatisfiedBy(context)
        let windows = hasSnapshots && hasWindows ? presentations(context) : []
        return QuotaPresentationReport(
            query: context.report.query, generatedAt: context.generatedAt,
            freshnessThresholdSeconds: configuration.freshnessThreshold,
            coverage: context.report.coverage, windows: windows
        )
    }

    private func presentations(_ context: Context) -> [QuotaWindowPresentation] {
        let candidates = context.report.snapshots.flatMap { snapshot in
            snapshot.windows.map { WindowCandidate(snapshot: snapshot, window: $0) }
        }
        let grouped = Dictionary(grouping: candidates, by: \.key)
        return grouped.values.compactMap { candidates in
            let ordered = candidates.sorted { lhs, rhs in
                if lhs.snapshot.timestamp != rhs.snapshot.timestamp {
                    return lhs.snapshot.timestamp < rhs.snapshot.timestamp
                }
                return lhs.snapshot.eventIdentity < rhs.snapshot.eventIdentity
            }
            guard let latest = ordered.last else { return nil }
            let latestReset = latest.window.resetsAt
            let discontinuity = zip(ordered, ordered.dropFirst()).contains { previous, next in
                guard let previousReset = previous.window.resetsAt,
                      let nextReset = next.window.resetsAt else { return false }
                return previousReset != nextReset
            }
            let age = context.generatedAt.timeIntervalSince(latest.snapshot.timestamp)
            return QuotaWindowPresentation(
                id: latest.key.identifier,
                scope: latest.snapshot.scope,
                scopeIdentifier: latest.snapshot.scopeIdentifier,
                limitID: latest.snapshot.limitID,
                limitName: latest.snapshot.limitName,
                planType: latest.snapshot.planType,
                slot: latest.window.slot,
                windowKind: latest.window.windowKind,
                windowMinutes: latest.window.windowMinutes,
                usedPercent: latest.window.usedPercent,
                remainingPercent: latest.window.remainingPercentDerived,
                resetsAt: latestReset,
                observedAt: latest.snapshot.timestamp,
                freshness: freshness(age),
                isResetDiscontinuity: discontinuity
            )
        }.sorted { lhs, rhs in
            if lhs.windowKind != rhs.windowKind {
                return windowOrder(lhs.windowKind) < windowOrder(rhs.windowKind)
            }
            return lhs.id < rhs.id
        }
    }

    private func freshness(_ age: TimeInterval) -> QuotaFreshness {
        guard age.isFinite else { return QuotaFreshness(state: .unknown, ageSeconds: nil) }
        let state: QuotaFreshnessState
        if age < 0 {
            state = .future
        } else if age > configuration.freshnessThreshold {
            state = .stale
        } else {
            state = .current
        }
        return QuotaFreshness(state: state, ageSeconds: age)
    }

    private func windowOrder(_ kind: UsageLimitWindowKind) -> Int {
        switch kind {
        case .fiveHour: 0
        case .weekly: 1
        case .other: 2
        case .unknown: 3
        }
    }
}

private struct WindowKey: Hashable {
    let scope: UsageLimitScope
    let scopeIdentifier: String?
    let limitID: String?
    let slot: UsageLimitWindowSlot

    var identifier: String {
        [scope.rawValue, scopeIdentifier ?? "unknown", limitID ?? "unknown", slot.rawValue]
            .joined(separator: "|")
    }
}

private struct WindowCandidate {
    let snapshot: UsageLimitSnapshotObservation
    let window: UsageLimitWindowObservation

    var key: WindowKey {
        WindowKey(
            scope: snapshot.scope, scopeIdentifier: snapshot.scopeIdentifier,
            limitID: snapshot.limitID, slot: window.slot
        )
    }
}
