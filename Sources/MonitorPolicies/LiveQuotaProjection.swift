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

/// Account scope must be known: a mixed or unknown scope could blend two accounts into one rate.
struct HasKnownAccountScopeSpec: Specification {
    func isSatisfiedBy(_ candidate: QuotaWindowCandidate) -> Bool {
        candidate.snapshot.accountScopeID != nil
            && candidate.snapshot.accountScopeState != .unknown && candidate.snapshot.accountScopeState != .mixed
            && candidate.snapshot.state == .observed && candidate.window.isComplete
    }
}

enum QuotaProjectionOutcome: Equatable {
    case projection(QuotaProjection)
    case quiet
    case unknown(String)
}

struct QuotaProjectionRule {
    func outcome(_ context: QuotaProjectionContext) -> QuotaProjectionOutcome {
        let configuration = context.configuration
        let ordered = context.series.sorted { $0.snapshot.timestamp < $1.snapshot.timestamp }
        guard let newest = ordered.last, HasKnownAccountScopeSpec().isSatisfiedBy(newest),
              let used = newest.window.usedPercent, let reset = newest.window.resetsAt else {
            return .unknown("The newest quota observation lacks a known account, used percent or reset time.")
        }
        // A pace that stopped (no fresh observation) or a window that already reset is no longer a
        // live projection, so the alert resolves; this is not missing evidence about the pace.
        let age = context.now.timeIntervalSince(newest.snapshot.timestamp)
        guard age >= 0, age <= configuration.projectionFreshness, reset > context.now else { return .quiet }
        if ordered.filter({ $0.snapshot.timestamp == newest.snapshot.timestamp })
            .contains(where: { $0.window.usedPercent != used || $0.window.resetsAt != reset }) {
            return .unknown("Conflicting quota values or resets share the newest observation time.")
        }
        // The same reset timestamp identifies one window instance; a different one is a new window.
        let start = newest.snapshot.timestamp.addingTimeInterval(-configuration.projectionWindow)
        let window = ordered.filter {
            $0.window.resetsAt == reset && $0.snapshot.timestamp >= start
                && HasKnownAccountScopeSpec().isSatisfiedBy($0)
        }
        guard let oldest = window.first, let oldestUsed = oldest.window.usedPercent else { return .quiet }
        let span = newest.snapshot.timestamp.timeIntervalSince(oldest.snapshot.timestamp)
        guard span >= configuration.projectionMinimumSpan else {
            let shortest = LiveRuleText.minutes(configuration.projectionMinimumSpan)
            return .unknown("Observed span is shorter than \(shortest).")
        }
        let values = window.compactMap(\.window.usedPercent)
        guard zip(values, values.dropFirst()).allSatisfy({ $0 <= $1 }) else {
            return .unknown("Used percent decreased inside one window, so the series is not comparable.")
        }
        let rate = (used - oldestUsed) / (span / 3_600)
        guard rate > 0, used < 100 else { return .quiet }
        let exhaustion = newest.snapshot.timestamp.addingTimeInterval((100 - used) / rate * 3_600)
        guard exhaustion < reset else { return .quiet }
        return .projection(QuotaProjection(
            latest: newest.snapshot.timestamp, usedPercent: used, ratePercentPerHour: rate,
            exhaustionAt: exhaustion, resetsAt: reset, observations: window.count, span: span
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
            switch QuotaProjectionRule().outcome(context) {
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
