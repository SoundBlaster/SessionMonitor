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
        return grouped.values.compactMap { candidates -> QuotaWindowPresentation? in
            let ordered = candidates.sorted { lhs, rhs in
                if lhs.snapshot.timestamp != rhs.snapshot.timestamp {
                    return lhs.snapshot.timestamp < rhs.snapshot.timestamp
                }
                return lhs.snapshot.sourceLine < rhs.snapshot.sourceLine
            }
            guard let latest = ordered.last else { return nil }
            let latestCandidates = ordered.filter { $0.snapshot.timestamp == latest.snapshot.timestamp }
            let isAmbiguous = Set(latestCandidates.map(\.fingerprint)).count > 1
            let latestReset = isAmbiguous ? nil : latest.window.resetsAt
            let resetCandidates = ordered.filter { $0.window.resetsAt != nil }
            let resetDiscontinuity = resetDiscontinuity(for: resetCandidates, isAmbiguous: isAmbiguous)
            let age = context.generatedAt.timeIntervalSince(latest.snapshot.timestamp)
            return QuotaWindowPresentation(
                id: latest.key.identifier,
                accountScopeID: latest.snapshot.accountScopeID,
                accountProfileID: latest.snapshot.accountProfileID,
                accountProfileLabel: latest.snapshot.accountProfileLabel,
                accountScopeState: latest.snapshot.accountScopeState,
                scope: latest.snapshot.scope,
                scopeIdentifier: latest.snapshot.scopeIdentifier,
                limitID: latest.snapshot.limitID,
                limitName: latest.snapshot.limitName,
                planType: latest.snapshot.planType,
                slot: latest.window.slot,
                windowKind: latest.window.windowKind,
                windowMinutes: latest.window.windowMinutes,
                usedPercent: isAmbiguous ? nil : latest.window.usedPercent,
                remainingPercent: isAmbiguous ? nil : latest.window.remainingPercentDerived,
                resetsAt: latestReset,
                observedAt: latest.snapshot.timestamp,
                freshness: freshness(age),
                isResetDiscontinuity: resetDiscontinuity != nil,
                resetDiscontinuity: resetDiscontinuity,
                isAmbiguous: isAmbiguous
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

    private func resetDiscontinuity(
        for candidates: [WindowCandidate], isAmbiguous: Bool
    ) -> QuotaResetDiscontinuity? {
        guard !isAmbiguous else { return nil }
        let transitions = Array(zip(candidates, candidates.dropFirst()))
        guard let transition = transitions.last(where: {
            $0.0.window.resetsAt != $0.1.window.resetsAt
        }), let previousReset = transition.0.window.resetsAt,
              let currentReset = transition.1.window.resetsAt else {
            return nil
        }
        return QuotaResetDiscontinuity(
            previousObservedAt: transition.0.snapshot.timestamp,
            previousUsedPercent: transition.0.window.usedPercent,
            previousRemainingPercent: transition.0.window.remainingPercentDerived,
            previousResetsAt: previousReset,
            currentObservedAt: transition.1.snapshot.timestamp,
            currentUsedPercent: transition.1.window.usedPercent,
            currentRemainingPercent: transition.1.window.remainingPercentDerived,
            currentResetsAt: currentReset
        )
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
    let accountScopeID: String?
    let scope: UsageLimitScope
    let scopeIdentifier: String?
    let limitIdentity: LimitIdentity
    let slot: UsageLimitWindowSlot

    var identifier: String {
        [accountScopeID ?? "unknown", scope.rawValue, scopeIdentifier ?? "unknown",
         limitIdentity.identifier, slot.rawValue]
            .joined(separator: "|")
    }

    enum LimitIdentity: Hashable {
        case id(String)
        case name(String)
        case anonymous

        var identifier: String {
            switch self {
            case let .id(value): value
            case let .name(value): "name:\(value)"
            case .anonymous: "unknown"
            }
        }
    }
}

private struct WindowCandidate {
    let snapshot: UsageLimitSnapshotObservation
    let window: UsageLimitWindowObservation

    var key: WindowKey {
        WindowKey(
            accountScopeID: snapshot.accountScopeID,
            scope: snapshot.scope, scopeIdentifier: snapshot.scopeIdentifier,
            limitIdentity: Self.limitIdentity(snapshot), slot: window.slot
        )
    }

    var fingerprint: Fingerprint {
        Fingerprint(
            state: snapshot.state, windowMinutes: window.windowMinutes,
            usedPercent: window.usedPercent, resetsAt: window.resetsAt,
            planType: snapshot.planType
        )
    }

    private static func limitIdentity(_ snapshot: UsageLimitSnapshotObservation)
        -> WindowKey.LimitIdentity {
        if let limitID = snapshot.limitID, !limitID.isEmpty {
            return .id(limitID)
        }
        if let limitName = snapshot.limitName, !limitName.isEmpty {
            return .name(limitName)
        }
        return .anonymous
    }
}

private struct Fingerprint: Hashable {
    let state: UsageLimitSnapshotState
    let windowMinutes: Int64?
    let usedPercent: Double?
    let resetsAt: Date?
    let planType: String?
}
