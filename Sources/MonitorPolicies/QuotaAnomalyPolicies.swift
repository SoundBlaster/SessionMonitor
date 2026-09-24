import Foundation
import MonitorCore
import SpecificationCore

public struct QuotaAnomalyConfiguration: Equatable, Sendable {
    public let minimumBaselineIntervals: Int
    public let minimumRateDeviation: Double
    public let minimumRobustZScore: Double
    public let freshnessThreshold: TimeInterval

    public init(
        minimumBaselineIntervals: Int = 5, minimumRateDeviation: Double = 10,
        minimumRobustZScore: Double = 3, freshnessThreshold: TimeInterval = 900
    ) {
        self.minimumBaselineIntervals = max(5, minimumBaselineIntervals)
        self.minimumRateDeviation = Self.positive(minimumRateDeviation, fallback: 10)
        self.minimumRobustZScore = Self.positive(minimumRobustZScore, fallback: 3)
        self.freshnessThreshold = Self.positive(freshnessThreshold, fallback: 900)
    }

    private static func positive(_ value: Double, fallback: Double) -> Double {
        value.isFinite && value > 0 ? value : fallback
    }
}

public struct QuotaAnomalyContext: Sendable {
    public let report: UsageLimitSnapshotReport
    public let generatedAt: Date
    public let configuration: QuotaAnomalyConfiguration

    public init(
        report: UsageLimitSnapshotReport, generatedAt: Date? = nil,
        configuration: QuotaAnomalyConfiguration = .init()
    ) {
        self.report = report
        self.generatedAt = generatedAt ?? report.generatedAt
        self.configuration = configuration
    }
}

private struct HasQuotaObservationsSpec: Specification {
    func isSatisfiedBy(_ candidate: QuotaAnomalyContext) -> Bool {
        !candidate.report.snapshots.isEmpty
    }
}

private struct QuotaRateShiftCandidate {
    let deviation: Double
    let robustZScore: Double
    let configuration: QuotaAnomalyConfiguration
}

private struct HasMaterialQuotaRateDeviationSpec: Specification {
    func isSatisfiedBy(_ candidate: QuotaRateShiftCandidate) -> Bool {
        abs(candidate.deviation) >= candidate.configuration.minimumRateDeviation
    }
}

private struct HasExceptionalQuotaRobustScoreSpec: Specification {
    func isSatisfiedBy(_ candidate: QuotaRateShiftCandidate) -> Bool {
        abs(candidate.robustZScore) >= candidate.configuration.minimumRobustZScore
    }
}

private struct IsQuotaRateShiftSpec: Specification {
    func isSatisfiedBy(_ candidate: QuotaRateShiftCandidate) -> Bool {
        HasMaterialQuotaRateDeviationSpec()
            .and(HasExceptionalQuotaRobustScoreSpec())
            .isSatisfiedBy(candidate)
    }
}

private struct IsMaterialQuotaRateDeviationSpec: Specification {
    let minimumDeviation: Double

    func isSatisfiedBy(_ candidate: Double) -> Bool {
        abs(candidate) >= minimumDeviation
    }
}

/// Converts imported observations into account/window-scoped outcomes. It never attributes
/// account-level quota movement to a session, even when a source event carries session context.
public struct QuotaAnomalyDecision: DecisionSpec {
    public typealias Context = QuotaAnomalyContext
    public typealias Result = [QuotaAnomalyAssessment]

    public init() {}

    public func decide(_ context: Context) -> Result? {
        assessments(for: context)
    }

    private func assessments(for context: Context) -> [QuotaAnomalyAssessment] {
        guard HasQuotaObservationsSpec().isSatisfiedBy(context) else {
            return [QuotaAnomalyAssessment(
                id: "quota:no-snapshots", outcome: .unknown, reason: .noSnapshots,
                evidence: DiagnosticEvidence(
                    unknown: [DiagnosticEvidenceItem(
                        source: "source_usage_limit_snapshots",
                        detail: "No imported quota observations are available for this query."
                    )], limitations: ["No quota usage value was inferred from session token totals."]
                )
            )]
        }

        let candidates = context.report.snapshots.flatMap { snapshot in
            snapshot.windows.map { QuotaWindowCandidate(snapshot: snapshot, window: $0) }
        }
        var output = context.report.snapshots.filter { $0.windows.isEmpty }.map {
            snapshotAssessment($0)
        }
        let groups = Dictionary(grouping: candidates, by: \.seriesKey)
        for (key, values) in groups {
            output.append(contentsOf: evaluate(values, key: key, context: context))
        }
        return output.sorted { $0.id < $1.id }
    }

    private func evaluate(
        _ candidates: [QuotaWindowCandidate], key: QuotaWindowSeriesKey, context: Context
    ) -> [QuotaAnomalyAssessment] {
        guard !candidates.isEmpty else { return [] }
        let ordered = candidates.sorted {
            if $0.snapshot.timestamp != $1.snapshot.timestamp {
                return $0.snapshot.timestamp < $1.snapshot.timestamp
            }
            return $0.snapshot.sourceLine < $1.snapshot.sourceLine
        }
        if let issue = seriesIssue(ordered, key: key, context: context) { return [issue] }

        let unique = uniqueSameTimestampValues(ordered)
        let resetGroups = splitAtResetChanges(unique)
        let discontinuities = resetGroups.discontinuities.map { previous, current in
            assessment(
                key: key, candidates: [previous, current], outcome: .resetDiscontinuity,
                detail: "The reset timestamp changed; usage across this boundary was not compared."
            )
        }
        return discontinuities + resetGroups.groups.flatMap { assessResetInterval($0, key: key, context: context) }
    }

    private func assessResetInterval(
        _ candidates: [QuotaWindowCandidate], key: QuotaWindowSeriesKey, context: Context
    ) -> [QuotaAnomalyAssessment] {
        guard candidates.count >= context.configuration.minimumBaselineIntervals + 2 else {
            return [assessment(
                key: key, candidates: candidates, outcome: .unknown, reason: .insufficientHistory,
                detail: "The reset interval does not contain enough prior usage intervals for a robust baseline."
            )]
        }
        guard let rates = percentageRates(candidates) else {
            return [assessment(
                key: key, candidates: candidates, outcome: .unknown, reason: .ambiguousObservation,
                detail: "Usage values or elapsed time are invalid for a percentage-rate comparison."
            )]
        }
        let concreteRates = rates
        let anomalies = shiftAssessments(candidates, rates: concreteRates, key: key, context: context)
        guard anomalies.isEmpty else { return anomalies }
        let baseline = Array(concreteRates.suffix(context.configuration.minimumBaselineIntervals))
        return [assessment(
            key: key, candidates: candidates, outcome: .stableUsage,
            detail: "Quota usage changes stayed within the configured robust-shift thresholds.",
            rate: concreteRates.last, baseline: Self.median(baseline)
        )]
    }

    private func percentageRates(_ candidates: [QuotaWindowCandidate]) -> [Double]? {
        let rates = zip(candidates, candidates.dropFirst()).map { previous, current -> Double? in
            let elapsed = current.snapshot.timestamp.timeIntervalSince(previous.snapshot.timestamp)
            guard elapsed > 0, elapsed.isFinite,
                  let before = previous.window.usedPercent,
                  let after = current.window.usedPercent,
                  before.isFinite, after.isFinite, (0...100).contains(before), (0...100).contains(after) else {
                return nil
            }
            return (after - before) / (elapsed / 3_600)
        }
        guard rates.allSatisfy({ $0?.isFinite == true }) else { return nil }
        return rates.compactMap { $0 }
    }

    private func shiftAssessments(
        _ candidates: [QuotaWindowCandidate], rates: [Double], key: QuotaWindowSeriesKey, context: Context
    ) -> [QuotaAnomalyAssessment] {
        var anomalies: [QuotaAnomalyAssessment] = []
        for index in context.configuration.minimumBaselineIntervals..<rates.count {
            let baseline = Array(rates[..<index])
            guard let median = Self.median(baseline), let mad = Self.median(baseline.map { abs($0 - median) }) else {
                continue
            }
            let current = rates[index]
            let deviation = current - median
            if mad == 0 {
                if IsMaterialQuotaRateDeviationSpec(
                    minimumDeviation: context.configuration.minimumRateDeviation
                ).isSatisfiedBy(deviation) {
                    anomalies.append(assessment(
                        key: key, candidates: Array(candidates[index...(index + 1)]),
                        outcome: .unknown, reason: .zeroMedianAbsoluteDeviation,
                        detail: "A robust score cannot be established because the baseline MAD is zero.",
                        rate: current, baseline: median
                    ))
                }
                continue
            }
            let robustZ = 0.674_489_75 * deviation / mad
            if IsQuotaRateShiftSpec().isSatisfiedBy(QuotaRateShiftCandidate(
                deviation: deviation, robustZScore: robustZ, configuration: context.configuration
            )) {
                anomalies.append(assessment(
                    key: key, candidates: Array(candidates[index...(index + 1)]),
                    outcome: .sharpShift, detail: "Quota usage rate departed sharply from its prior robust baseline.",
                    rate: current, baseline: median, robustZ: robustZ
                ))
            }
        }
        return anomalies
    }

    private func seriesIssue(
        _ candidates: [QuotaWindowCandidate], key: QuotaWindowSeriesKey, context: Context
    ) -> QuotaAnomalyAssessment? {
        guard let first = candidates.first else { return nil }
        let metadata = first.snapshot
        if metadata.accountScopeID == nil
            || metadata.accountScopeState != .assigned && metadata.accountScopeState != .explicitIdentity {
            return assessment(
                key: key, candidates: candidates, outcome: .notApplicable, reason: .unknownAccountScope,
                detail: "The quota observations do not have a stable, resolved account scope."
            )
        }
        guard key.scope != UsageLimitScope.unknown.rawValue, key.limitIdentity != nil,
              key.windowMinutes.map({ $0 > 0 }) == true,
              key.scope != UsageLimitScope.modelPool.rawValue || key.scopeIdentifier != nil else {
            return assessment(
                key: key, candidates: candidates, outcome: .notApplicable, reason: .missingWindowIdentity,
                detail: "The quota limit or window identity is incomplete, so observations cannot be compared."
            )
        }
        if let incomplete = candidates.first(where: { $0.snapshot.state != .observed }),
           let reason = incompleteReason(for: incomplete.snapshot.state) {
            return assessment(
                key: key, candidates: candidates, outcome: .unknown, reason: reason,
                detail: "At least one snapshot in this quota series has incomplete or unsupported coverage."
            )
        }
        guard let latest = candidates.last else { return nil }
        let latestAge = context.generatedAt.timeIntervalSince(latest.snapshot.timestamp)
        guard latestAge.isFinite, latestAge >= 0, latestAge <= context.configuration.freshnessThreshold else {
            return assessment(
                key: key, candidates: candidates, outcome: .unknown, reason: .staleObservation,
                detail: "The latest quota observation is stale or has a future timestamp."
            )
        }
        if candidates.contains(where: { $0.window.resetsAt == nil }) {
            return assessment(
                key: key, candidates: candidates, outcome: .unknown, reason: .missingReset,
                detail: "A reset timestamp is missing, so the reset interval cannot be established."
            )
        }
        guard !hasConflictingSameTimestampValues(candidates) else {
            return assessment(
                key: key, candidates: candidates, outcome: .unknown, reason: .ambiguousObservation,
                detail: "Conflicting quota values share the same account, window and observation timestamp."
            )
        }
        return nil
    }

    func incompleteReason(for state: UsageLimitSnapshotState) -> QuotaAnomalyReason? {
        switch state {
        case .observed: nil
        case .partial, .noWindowData: .incompleteCoverage
        case .unsupportedSchema: .unsupportedSnapshot
        }
    }
}

private extension QuotaAnomalyDecision {
    func snapshotAssessment(_ snapshot: UsageLimitSnapshotObservation) -> QuotaAnomalyAssessment {
        let reason: QuotaAnomalyReason = switch snapshot.state {
        case .observed: .missingWindowIdentity
        case .partial: .incompleteCoverage
        case .noWindowData: .incompleteCoverage
        case .unsupportedSchema: .unsupportedSnapshot
        }
        let detail = "Quota event has no usable window observation (snapshot state: \(snapshot.state.rawValue))."
        return QuotaAnomalyAssessment(
            id: "quota:event:\(snapshot.id)", outcome: .unknown, reason: reason,
            accountScopeID: snapshot.accountScopeID, accountProfileID: snapshot.accountProfileID,
            accountProfileLabel: snapshot.accountProfileLabel, accountScopeState: snapshot.accountScopeState,
            scope: snapshot.scope, scopeIdentifier: snapshot.scopeIdentifier,
            limitID: snapshot.limitID, limitName: snapshot.limitName,
            previousObservedAt: nil, currentObservedAt: snapshot.timestamp,
            evidence: DiagnosticEvidence(
                observed: [evidenceItem(snapshot, detail: detail)],
                unknown: [DiagnosticEvidenceItem(
                    source: "source_usage_limit_snapshots", detail: "A comparable quota window is unavailable."
                )], limitations: ["No quota use was inferred from session token totals."]
            )
        )
    }

    func assessment(
        key: QuotaWindowSeriesKey, candidates: [QuotaWindowCandidate], outcome: QuotaAnomalyOutcome,
        reason: QuotaAnomalyReason? = nil, detail: String, rate: Double? = nil,
        baseline: Double? = nil, robustZ: Double? = nil
    ) -> QuotaAnomalyAssessment {
        let latest = candidates.last
        let previous = candidates.dropLast().last
        let first = candidates.first?.snapshot
        let lines = candidates.map { $0.snapshot.sourceLine }.sorted()
        let detailWithValues: String
        if let previous, let latest {
            detailWithValues = "\(detail) usedPercent \(previous.window.usedPercent.map(Self.format) ?? "unknown")% → "
                + "\(latest.window.usedPercent.map(Self.format) ?? "unknown")%; observed at "
                + "\(ISO8601DateFormatter().string(from: previous.snapshot.timestamp)) and "
                + "\(ISO8601DateFormatter().string(from: latest.snapshot.timestamp))."
        } else {
            detailWithValues = detail
        }
        return QuotaAnomalyAssessment(
            id: "quota:\(key.stableID):\(outcome.rawValue):\(lines.map(String.init).joined(separator: ","))",
            outcome: outcome, reason: reason,
            accountScopeID: first?.accountScopeID, accountProfileID: first?.accountProfileID,
            accountProfileLabel: first?.accountProfileLabel, accountScopeState: first?.accountScopeState ?? .unknown,
            scope: first?.scope, scopeIdentifier: first?.scopeIdentifier, limitID: first?.limitID,
            limitName: first?.limitName, slot: latest?.window.slot, windowMinutes: latest?.window.windowMinutes,
            resetsAt: latest?.window.resetsAt, previousObservedAt: previous?.snapshot.timestamp,
            currentObservedAt: latest?.snapshot.timestamp, rateChangePercentagePointsPerHour: rate,
            baselineMedianPercentagePointsPerHour: baseline, robustZScore: robustZ,
            evidence: DiagnosticEvidence(
                observed: candidates.map { evidenceItem($0.snapshot, detail: detailWithValues) },
                inference: [DiagnosticEvidenceItem(
                    source: "specification_core_policy",
                    detail: "QuotaAnomalyDecision classified this matched account/window/reset series as "
                        + "\(outcome.rawValue).", sourceLines: lines
                )],
                unknown: [DiagnosticEvidenceItem(
                    source: "source_usage_limit_snapshots",
                    detail: "Quota observations are account-level; they do not prove which session caused usage.",
                    sourceLines: lines
                )],
                limitations: ["Account-level quota movement is never attributed to an individual session."]
            )
        )
    }

    func evidenceItem(_ snapshot: UsageLimitSnapshotObservation, detail: String) -> DiagnosticEvidenceItem {
        DiagnosticEvidenceItem(
            source: "source_usage_limit_snapshots", detail: detail,
            sessionIDs: [], sourceLines: [snapshot.sourceLine]
        )
    }

    func hasConflictingSameTimestampValues(_ candidates: [QuotaWindowCandidate]) -> Bool {
        Dictionary(grouping: candidates, by: { $0.snapshot.timestamp }).values.contains { group in
            Set(group.map { "\($0.window.usedPercent ?? -1)|\($0.window.resetsAt?.timeIntervalSince1970 ?? -1)" })
                .count > 1
        }
    }

    func uniqueSameTimestampValues(_ candidates: [QuotaWindowCandidate]) -> [QuotaWindowCandidate] {
        var seen = Set<String>()
        return candidates.filter { candidate in
            let key = "\(candidate.snapshot.timestamp.timeIntervalSince1970)|"
                + "\(candidate.window.usedPercent ?? -1)|\(candidate.window.resetsAt?.timeIntervalSince1970 ?? -1)"
            return seen.insert(key).inserted
        }
    }

    func splitAtResetChanges(
        _ candidates: [QuotaWindowCandidate]
    ) -> (groups: [[QuotaWindowCandidate]], discontinuities: [(QuotaWindowCandidate, QuotaWindowCandidate)]) {
        guard let first = candidates.first else { return ([], []) }
        var groups: [[QuotaWindowCandidate]] = [[first]]
        var discontinuities: [(QuotaWindowCandidate, QuotaWindowCandidate)] = []
        for candidate in candidates.dropFirst() {
            guard let previous = groups[groups.count - 1].last else { continue }
            if previous.window.resetsAt != candidate.window.resetsAt {
                discontinuities.append((previous, candidate))
                groups.append([candidate])
            } else {
                groups[groups.count - 1].append(candidate)
            }
        }
        return (groups, discontinuities)
    }

    static func median(_ values: [Double]) -> Double? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    static func format(_ value: Double) -> String { String(format: "%.2f", value) }
}
