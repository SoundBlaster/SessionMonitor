import Foundation
import MonitorCore

/// Thresholds that turn existing analytics into alert candidates. They do not change the analytics.
public struct AlertSignalConfiguration: Equatable, Sendable {
    /// A current quota window at or below this remaining percentage raises a warning.
    public let quotaLowRemainingPercent: Double
    /// A current quota window at or below this remaining percentage raises an error.
    public let quotaCriticalRemainingPercent: Double
    /// Only quota rate shifts observed this recently are live signals; older shifts are history.
    public let recentQuotaShiftWindow: TimeInterval
    /// Below-threshold cache coverage is informational: cache hit alone does not prove waste.
    public let cacheHitThreshold: CacheHitThreshold

    public init(
        quotaLowRemainingPercent: Double = 20, quotaCriticalRemainingPercent: Double = 5,
        recentQuotaShiftWindow: TimeInterval = 3_600, cacheHitThreshold: CacheHitThreshold = .default
    ) {
        let critical = Self.percent(quotaCriticalRemainingPercent, fallback: 5)
        self.quotaCriticalRemainingPercent = critical
        self.quotaLowRemainingPercent = max(critical, Self.percent(quotaLowRemainingPercent, fallback: 20))
        self.recentQuotaShiftWindow = recentQuotaShiftWindow.isFinite && recentQuotaShiftWindow > 0
            ? recentQuotaShiftWindow : 3_600
        self.cacheHitThreshold = cacheHitThreshold
    }

    private static func percent(_ value: Double, fallback: Double) -> Double {
        value.isFinite && (0...100).contains(value) ? value : fallback
    }
}

/// Candidates plus every scope they were evaluated in, so absent signals can resolve.
public struct AlertSignalBatch: Equatable, Sendable {
    public var scopes: Set<AlertScope>
    public var candidates: [AlertCandidate]

    public init(scopes: Set<AlertScope> = [], candidates: [AlertCandidate] = []) {
        self.scopes = scopes
        self.candidates = candidates
    }

    public mutating func merge(_ other: AlertSignalBatch) {
        scopes.formUnion(other.scopes)
        candidates.append(contentsOf: other.candidates)
    }

    public func evaluation(at observedAt: Date) -> AlertEvaluation {
        AlertEvaluation(scopes: scopes, candidates: candidates, observedAt: observedAt)
    }
}

/// Pure adapters from existing analytics contracts to alert candidates.
public enum AlertSignals {
    public static let databaseScope = AlertScope("diagnostics:database")
    public static let quotaShiftScope = AlertScope("quota:shift")
    public static let quotaRemainingScope = AlertScope("quota:remaining")

    /// Scopes are per source, so evaluating one source never resolves another source's alerts.
    public static func anomalyScope(_ sessionID: String) -> AlertScope {
        AlertScope("anomaly:session:\(sessionID)")
    }

    public static func cacheScope(_ sessionID: String) -> AlertScope {
        AlertScope("cache:session:\(sessionID)")
    }

    /// Session findings come from `AnomalyFinding.id` (`kind|sessions|responses|lines`); the key keeps
    /// only kind and sessions, so new evidence for the same condition updates rather than re-raises.
    /// Database-wide findings use their stable IDs. Every evaluated session scope is listed so a
    /// session whose finding disappeared resolves.
    public static func diagnostics(_ report: DiagnosticReport, evaluatedSessions: [String]) -> AlertSignalBatch {
        var batch = AlertSignalBatch(scopes: Set(evaluatedSessions.map(anomalyScope)).union([databaseScope]))
        for finding in report.findings {
            let parts = finding.id.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            let isSessionFinding = finding.coverage != nil && parts.count >= 2
                && finding.affectedSessions.count == 1
            let kind = parts.first ?? finding.id
            let scope = isSessionFinding ? anomalyScope(finding.affectedSessions[0]) : databaseScope
            let key = isSessionFinding ? "anomaly|\(kind)|\(parts[1])" : "diagnostics|\(finding.id)"
            batch.scopes.insert(scope)
            batch.candidates.append(AlertCandidate(
                key: key, scope: scope, source: isSessionFinding ? .anomaly : .importDiagnostics, kind: kind,
                severity: finding.severity, title: finding.title,
                message: "\(finding.explanation) Next: \(finding.suggestedNextAction)",
                sessionIDs: finding.affectedSessions, coverage: finding.coverage ?? .observed,
                evidence: finding.evidence
            ))
        }
        return batch
    }

    /// Only recent `sharp_shift` outcomes are live. Unknown and stable outcomes never alert; quota
    /// movement stays account-level and is never attributed to a session.
    public static func quotaShifts(
        _ assessments: [QuotaAnomalyAssessment], now: Date, configuration: AlertSignalConfiguration = .init()
    ) -> AlertSignalBatch {
        var batch = AlertSignalBatch(scopes: [quotaShiftScope])
        let recent = assessments.filter { assessment in
            guard assessment.outcome == .sharpShift, let observed = assessment.currentObservedAt else { return false }
            let age = now.timeIntervalSince(observed)
            return age >= 0 && age <= configuration.recentQuotaShiftWindow
        }
        var seen = Set<String>()
        let newestFirst = recent.sorted {
            ($0.currentObservedAt ?? .distantPast) > ($1.currentObservedAt ?? .distantPast)
        }
        for assessment in newestFirst {
            let series = [
                assessment.accountScopeID ?? "unknown", assessment.limitID ?? assessment.limitName ?? "unknown",
                assessment.slot?.rawValue ?? "unknown", assessment.windowMinutes.map(String.init) ?? "unknown"
            ].joined(separator: "|")
            guard seen.insert(series).inserted else { continue }
            let account = assessment.accountProfileLabel ?? assessment.accountProfileID ?? "account"
            let rate = assessment.rateChangePercentagePointsPerHour.map { String(format: "%.1f", $0) } ?? "unknown"
            let baseline = assessment.baselineMedianPercentagePointsPerHour.map { String(format: "%.1f", $0) }
                ?? "unknown"
            batch.candidates.append(AlertCandidate(
                key: "quota|sharp_shift|\(series)", scope: quotaShiftScope, source: .quota, kind: "sharp_shift",
                severity: .warning, title: "Quota usage rate shift",
                message: "\(account) quota is moving at \(rate) pp/h against a baseline of \(baseline) pp/h.",
                accountScopeID: assessment.accountScopeID, evidence: assessment.evidence
            ))
        }
        return batch
    }

    /// Low remaining quota from the latest observation per window. A stale or ambiguous window keeps
    /// an existing alert visible with unknown coverage instead of claiming the quota recovered.
    public static func quotaRemaining(
        _ report: QuotaPresentationReport, configuration: AlertSignalConfiguration = .init()
    ) -> AlertSignalBatch {
        var batch = AlertSignalBatch(scopes: [quotaRemainingScope])
        for window in report.windows {
            guard let remaining = window.remainingPercent,
                  remaining <= configuration.quotaLowRemainingPercent else { continue }
            let isCurrent = window.freshness.state == .current && !window.isAmbiguous
            let isCritical = remaining <= configuration.quotaCriticalRemainingPercent
            let severity: DiagnosticSeverity = isCritical ? .error : .warning
            let account = window.accountProfileLabel ?? window.accountProfileID ?? "account"
            let reset = window.resetsAt.map { " Resets at \(ISO8601DateFormatter().string(from: $0))." } ?? ""
            batch.candidates.append(AlertCandidate(
                key: "quota|remaining|\(window.id)", scope: quotaRemainingScope, source: .quota,
                kind: "low_remaining", severity: severity, title: "Low remaining quota",
                message: "\(account) \(window.windowKind.rawValue) window has "
                    + "\(String(format: "%.0f", remaining))% remaining.\(reset)",
                accountScopeID: window.accountScopeID,
                coverage: isCurrent
                    ? .observed : .unknown(reason: "The latest quota observation is stale or ambiguous."),
                evidence: DiagnosticEvidence(observed: [DiagnosticEvidenceItem(
                    source: "source_usage_limit_snapshots",
                    detail: "Latest observation at \(ISO8601DateFormatter().string(from: window.observedAt)) reports "
                        + "\(String(format: "%.1f", 100 - remaining))% used."
                )], limitations: ["Remaining percentage is derived from observed used percentage."])
            ))
        }
        return batch
    }

    /// Informational only: low cache coverage is a diagnostic hint, not proof of avoidable cost.
    public static func cacheThreshold(
        _ sessions: [SessionSummary], configuration: AlertSignalConfiguration = .init()
    ) -> AlertSignalBatch {
        let policy = CacheHitThresholdPolicy(threshold: configuration.cacheHitThreshold)
        var batch = AlertSignalBatch(scopes: Set(sessions.map { cacheScope($0.id) }))
        for session in sessions {
            guard case let .knownBelowThreshold(hit, threshold) = policy.presentation(for: session) else {
                continue
            }
            batch.candidates.append(AlertCandidate(
                key: "cache_threshold|\(session.id)", scope: cacheScope(session.id), source: .cacheThreshold,
                kind: "below_threshold", severity: .info, title: "Cache hit below threshold",
                message: "Session cache hit is \(String(format: "%.1f", hit))%, "
                    + "below \(String(format: "%.0f", threshold))%.",
                sessionIDs: [session.id],
                evidence: DiagnosticEvidence(
                    observed: [DiagnosticEvidenceItem(
                        source: "confirmed",
                        detail: "\(session.totals.cachedInputTokens) cached of "
                            + "\(session.totals.inputTokens) input tokens.",
                        sessionIDs: [session.id]
                    )],
                    limitations: ["Cache hit ratio alone does not show whether usage was avoidable."]
                )
            ))
        }
        return batch
    }
}
