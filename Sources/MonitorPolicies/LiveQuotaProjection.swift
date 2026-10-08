import Foundation
import MonitorCore
import SpecificationCore

/// One quota series projected linearly from its own recent observations of the current window.
struct QuotaProjectionContext {
    let series: [QuotaWindowCandidate]
    let now: Date
    let configuration: LiveRuleConfiguration
}

struct QuotaProjection: Equatable {
    let latest: Date
    let usedPercent: Double
    let ratePercentPerHour: Double
    let exhaustionAt: Date
    let resetsAt: Date
    let observations: Int
    let span: TimeInterval
}

enum QuotaProjectionOutcome: Equatable {
    case projection(QuotaProjection)
    case quiet
    case unknown(String)
}

// MARK: - Measures

extension QuotaProjectionContext {
    var ordered: [QuotaWindowCandidate] { series.sorted { $0.snapshot.timestamp < $1.snapshot.timestamp } }

    var newest: QuotaWindowCandidate? { ordered.last }

    var used: Double? { newest?.window.usedPercent }

    var reset: Date? { newest?.window.resetsAt }

    /// The same reset timestamp identifies one window instance; a different one is a new window.
    var windowSeries: [QuotaWindowCandidate] {
        guard let newest, let reset else { return [] }
        let start = newest.snapshot.timestamp.addingTimeInterval(-configuration.projectionWindow)
        return ordered.filter {
            $0.window.resetsAt == reset && $0.snapshot.timestamp >= start
                && HasKnownAccountScopeSpec().isSatisfiedBy($0)
        }
    }

    var span: TimeInterval {
        guard let newest, let oldest = windowSeries.first else { return 0 }
        return newest.snapshot.timestamp.timeIntervalSince(oldest.snapshot.timestamp)
    }

    /// Percentage points per hour between the oldest and newest observation of the current window.
    var rate: Double? {
        guard let used, let oldestUsed = windowSeries.first?.window.usedPercent, span > 0 else { return nil }
        return (used - oldestUsed) / (span / 3_600)
    }

    var exhaustionAt: Date? {
        guard let newest, let used, let rate, rate > 0, used < 100 else { return nil }
        return newest.snapshot.timestamp.addingTimeInterval((100 - used) / rate * 3_600)
    }
}

// MARK: - Specifications

/// Account scope must be known: a mixed or unknown scope could blend two accounts into one rate.
struct HasKnownAccountScopeSpec: Specification {
    func isSatisfiedBy(_ candidate: QuotaWindowCandidate) -> Bool {
        candidate.snapshot.accountScopeID != nil
            && candidate.snapshot.accountScopeState != .unknown && candidate.snapshot.accountScopeState != .mixed
            && candidate.snapshot.state == .observed && candidate.window.isComplete
    }
}

struct HasKnownNewestObservationSpec: Specification {
    func isSatisfiedBy(_ context: QuotaProjectionContext) -> Bool {
        guard let newest = context.newest else { return false }
        return HasKnownAccountScopeSpec().isSatisfiedBy(newest) && context.used != nil && context.reset != nil
    }
}

/// A pace that stopped (no fresh observation) or a window that already reset is no longer a live projection.
struct IsLiveProjectionSpec: Specification {
    func isSatisfiedBy(_ context: QuotaProjectionContext) -> Bool {
        guard let newest = context.newest, let reset = context.reset else { return false }
        let age = context.now.timeIntervalSince(newest.snapshot.timestamp)
        return age >= 0 && age <= context.configuration.projectionFreshness && reset > context.now
    }
}

/// Observations of one instant that disagree on value or reset make the window identity ambiguous.
struct HasUnambiguousNewestSpec: Specification {
    func isSatisfiedBy(_ context: QuotaProjectionContext) -> Bool {
        guard let newest = context.newest else { return false }
        return !context.ordered.contains {
            $0.snapshot.timestamp == newest.snapshot.timestamp
                && ($0.window.usedPercent != context.used || $0.window.resetsAt != context.reset)
        }
    }
}

struct HasProjectionSpanSpec: Specification {
    func isSatisfiedBy(_ context: QuotaProjectionContext) -> Bool {
        context.span >= context.configuration.projectionMinimumSpan
    }
}

/// Used percent that falls inside one window means the series is not comparable.
struct IsMonotonicUsageSpec: Specification {
    func isSatisfiedBy(_ context: QuotaProjectionContext) -> Bool {
        let values = context.windowSeries.compactMap(\.window.usedPercent)
        return zip(values, values.dropFirst()).allSatisfy { $0 <= $1 }
    }
}

struct HasRisingUsageSpec: Specification {
    func isSatisfiedBy(_ context: QuotaProjectionContext) -> Bool { context.exhaustionAt != nil }
}

struct ExhaustsBeforeResetSpec: Specification {
    func isSatisfiedBy(_ context: QuotaProjectionContext) -> Bool {
        guard let exhaustion = context.exhaustionAt, let reset = context.reset else { return false }
        return exhaustion < reset
    }
}

// MARK: - Decision

struct QuotaProjectionDecision: DecisionSpec {
    typealias Context = QuotaProjectionContext
    typealias Result = QuotaProjectionOutcome

    typealias Match = FirstMatchSpec<QuotaProjectionContext, QuotaProjectionOutcome>
    typealias Blocker = Match.SpecificationPair

    private static func requiring<S: Specification>(_ spec: S, otherwise outcome: QuotaProjectionOutcome) -> Blocker
        where S.T == QuotaProjectionContext {
        (AnySpecification(spec.not()), outcome)
    }

    /// The first unmet requirement decides: `quiet` resolves an existing alert, `unknown` leaves it.
    private static func blockers() -> Match {
        let blockers: [Blocker] = [
            requiring(
                HasKnownNewestObservationSpec(),
                otherwise: .unknown("The newest quota observation lacks a known account, used percent or reset time.")
            ),
            requiring(IsLiveProjectionSpec(), otherwise: .quiet),
            requiring(
                HasUnambiguousNewestSpec(),
                otherwise: .unknown("Conflicting quota values or resets share the newest observation time.")
            ),
            requiring(HasProjectionSpanSpec(), otherwise: .unknown("The observed span is too short for a pace.")),
            requiring(
                IsMonotonicUsageSpec(),
                otherwise: .unknown("Used percent decreased inside one window, so the series is not comparable.")
            ),
            requiring(HasRisingUsageSpec(), otherwise: .quiet),
            requiring(ExhaustsBeforeResetSpec(), otherwise: .quiet)
        ]
        return Match(blockers)
    }

    func decide(_ context: QuotaProjectionContext) -> QuotaProjectionOutcome? {
        if let blocked = Self.blockers().decide(context) { return blocked }
        guard let newest = context.newest, let used = context.used, let reset = context.reset,
              let rate = context.rate, let exhaustion = context.exhaustionAt else { return .quiet }
        return .projection(QuotaProjection(
            latest: newest.snapshot.timestamp, usedPercent: used, ratePercentPerHour: rate,
            exhaustionAt: exhaustion, resetsAt: reset, observations: context.windowSeries.count,
            span: context.span
        ))
    }
}

extension LiveRules {
    /// `activeSeriesIDs` are the series of currently active projection alerts.
    /// Raises when the observed pace in the current quota window exhausts it before the window resets.
    /// Account-level: never attributed to a session. Each series has its own scope and is only evaluated
    /// when it gave a clear answer, so an unknown series keeps its alert instead of resolving it.
    public static func quotaProjectionScope(_ seriesID: String) -> AlertScope {
        AlertScope("quota:projection:\(seriesID)")
    }

    public static func quotaProjection(
        _ report: UsageLimitSnapshotReport, now: Date, activeSeriesIDs: Set<String> = [],
        configuration: LiveRuleConfiguration = .init()
    ) -> AlertSignalBatch {
        var series: [QuotaWindowSeriesKey: [QuotaWindowCandidate]] = [:]
        for snapshot in report.snapshots {
            for window in snapshot.windows {
                let candidate = QuotaWindowCandidate(snapshot: snapshot, window: window)
                series[candidate.seriesKey, default: []].append(candidate)
            }
        }
        var batch = AlertSignalBatch()
        for key in series.keys.sorted(by: { $0.stableID < $1.stableID }) {
            let context = QuotaProjectionContext(series: series[key] ?? [], now: now, configuration: configuration)
            switch QuotaProjectionDecision().decide(context) ?? .quiet {
            case let .projection(projection):
                batch.candidates.append(candidate(key, series[key] ?? [], projection, now: now, configuration))
            case .quiet:
                batch.scopes.insert(quotaProjectionScope(key.stableID))
            case .unknown:
                continue
            }
        }
        // An alerting series with no observation at all in the report has no live pace any more.
        let reported = Set(series.keys.map(\.stableID))
        for id in activeSeriesIDs where !reported.contains(id) { batch.scopes.insert(quotaProjectionScope(id)) }
        return batch
    }

    private static func candidate(
        _ key: QuotaWindowSeriesKey, _ series: [QuotaWindowCandidate], _ projection: QuotaProjection, now: Date,
        _ configuration: LiveRuleConfiguration
    ) -> AlertCandidate {
        let newest = series.max { $0.snapshot.timestamp < $1.snapshot.timestamp }
        let account = newest?.snapshot.accountProfileLabel ?? newest?.snapshot.accountProfileID ?? "account"
        let kind = newest?.window.windowKind.rawValue ?? "window"
        let formatter = ISO8601DateFormatter()
        let remaining = projection.exhaustionAt.timeIntervalSince(now)
        return AlertCandidate(
            key: "quota|projected_exhaustion|\(key.stableID)", scope: quotaProjectionScope(key.stableID),
            source: .quota,
            kind: "projected_exhaustion",
            severity: remaining <= configuration.criticalExhaustion ? .error : .warning,
            title: "Quota projected to run out before reset",
            message: "At the current pace the \(account) \(kind) window reaches 100% around "
                + "\(formatter.string(from: projection.exhaustionAt)), before it resets at "
                + "\(formatter.string(from: projection.resetsAt)). Next: slow down or switch accounts.",
            accountScopeID: newest?.snapshot.accountScopeID,
            evidence: DiagnosticEvidence(
                observed: [DiagnosticEvidenceItem(
                    source: "source_usage_limit_snapshots",
                    detail: "\(projection.observations) observations over \(LiveRuleText.minutes(projection.span)); "
                        + "used \(String(format: "%.1f", projection.usedPercent))% at "
                        + "\(formatter.string(from: projection.latest))."
                )],
                inference: [DiagnosticEvidenceItem(
                    source: "linear_projection",
                    detail: "Rate \(String(format: "%.1f", projection.ratePercentPerHour)) pp/h over the observed span."
                )],
                limitations: ["Linear extrapolation of the last observations; a change of pace invalidates it."]
            )
        )
    }
}
