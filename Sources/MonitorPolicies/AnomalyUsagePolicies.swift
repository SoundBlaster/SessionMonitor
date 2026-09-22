import Foundation
import MonitorCore
import SpecificationCore

private struct HasHighAbsoluteUsageSpec: Specification {
    let configuration: AnomalyPolicyConfiguration

    func isSatisfiedBy(_ candidate: AnomalyPolicyContext) -> Bool {
        candidate.session.totals.inputTokens >= configuration.minimumAbsoluteInputTokens
            || candidate.session.totals.requests >= configuration.minimumAbsoluteRequests
    }
}

private struct HasDominantSessionSpec: Specification {
    let configuration: AnomalyPolicyConfiguration

    func isSatisfiedBy(_ candidate: AnomalyPolicyContext) -> Bool {
        let totalInput = candidate.cohort.reduce(Int64(0)) { partial, session in
            let (sum, overflow) = partial.addingReportingOverflow(session.totals.inputTokens)
            return overflow ? Int64.max : sum
        }
        guard totalInput >= configuration.minimumDominantInputTokens, totalInput > 0 else { return false }
        return Double(candidate.session.totals.inputTokens) / Double(totalInput)
            >= configuration.dominantSessionShare
    }
}

private struct HasUncachedBurstSpec: Specification {
    let configuration: AnomalyPolicyConfiguration

    func isSatisfiedBy(_ candidate: AnomalyPolicyContext) -> Bool {
        AnomalyPolicySupport.requestPoints(candidate).contains { point in
            guard let input = AnomalyPolicySupport.inputTokens(point), input > 0,
                  let cached = point.cachedInputTokens,
                  let uncached = point.uncachedInputTokens else { return false }
            return uncached >= configuration.minimumUncachedInputTokens
                && Double(uncached) / Double(input) >= configuration.cacheChangeRatio
                && cached >= 0
        }
    }
}

struct HighAbsoluteUsageDecision: DecisionSpec {
    typealias Context = AnomalyPolicyContext
    typealias Result = AnomalyFinding
    let configuration: AnomalyPolicyConfiguration

    func decide(_ context: Context) -> Result? {
        guard HasHighAbsoluteUsageSpec(configuration: configuration).isSatisfiedBy(context) else { return nil }
        let totals = context.session.totals
        return AnomalyFinding(
            kind: .highAbsoluteUsage, title: "High absolute usage",
            reason: "This session exceeds an absolute input or response threshold; "
                + "cache hit ratio does not reduce the measured usage.",
            severity: .warning,
            evidence: DiagnosticEvidence(observed: [DiagnosticEvidenceItem(
                source: "confirmed",
                detail: "Session contains \(totals.inputTokens) input tokens and \(totals.requests) responses.",
                sessionIDs: [context.session.id]
            )], inference: [DiagnosticEvidenceItem(
                source: "specification_core_policy",
                detail: "HasHighAbsoluteUsageSpec satisfied the configured absolute threshold.",
                sessionIDs: [context.session.id]
            )]), confidence: .high, coverage: .observed,
            affectedSessions: [context.session.id],
            suggestedNextAction: "Review the session's request count and input volume before attributing the cost "
                + "to cache misses."
        )
    }
}

struct DominantSessionDecision: DecisionSpec {
    typealias Context = AnomalyPolicyContext
    typealias Result = AnomalyFinding
    let configuration: AnomalyPolicyConfiguration

    func decide(_ context: Context) -> Result? {
        guard HasDominantSessionSpec(configuration: configuration).isSatisfiedBy(context) else { return nil }
        let total = context.cohort.reduce(Int64(0)) { partial, session in
            let (sum, overflow) = partial.addingReportingOverflow(session.totals.inputTokens)
            return overflow ? Int64.max : sum
        }
        let share = Double(context.session.totals.inputTokens) / Double(max(total, 1))
        return AnomalyFinding(
            kind: .dominantSession, title: "Dominant session usage",
            reason: "One session accounts for a large share of the selected cohort's input volume.",
            severity: .info,
            evidence: DiagnosticEvidence(observed: [DiagnosticEvidenceItem(
                source: "confirmed",
                detail: "Session contributes \(Int((share * 100).rounded()))% of \(total) cohort input tokens.",
                sessionIDs: [context.session.id]
            )], inference: [DiagnosticEvidenceItem(
                source: "specification_core_policy",
                detail: "HasDominantSessionSpec satisfied the configured share and volume thresholds.",
                sessionIDs: [context.session.id]
            )]), confidence: .medium, coverage: .observed,
            affectedSessions: [context.session.id],
            suggestedNextAction: "Inspect this session and its related parent/subagent sessions as one usage group."
        )
    }
}

struct UncachedBurstDecision: DecisionSpec {
    typealias Context = AnomalyPolicyContext
    typealias Result = AnomalyFinding
    let configuration: AnomalyPolicyConfiguration

    func decide(_ context: Context) -> Result? {
        guard HasUncachedBurstSpec(configuration: configuration).isSatisfiedBy(context) else { return nil }
        let point = AnomalyPolicySupport.requestPoints(context).first { point in
            guard let input = AnomalyPolicySupport.inputTokens(point), let cached = point.cachedInputTokens,
                  let uncached = point.uncachedInputTokens else { return false }
            return uncached >= configuration.minimumUncachedInputTokens
                && Double(uncached) / Double(input) >= configuration.cacheChangeRatio && cached >= 0
        }
        guard let point, let input = AnomalyPolicySupport.inputTokens(point),
              let uncached = point.uncachedInputTokens else { return nil }
        return AnomalyFinding(
            kind: .uncachedBurst, title: "Uncached input burst",
            reason: "A request contains a large absolute uncached-input burst.", severity: .warning,
            evidence: DiagnosticEvidence(observed: [DiagnosticEvidenceItem(
                source: "confirmed",
                detail: "Request contains \(uncached) uncached tokens out of \(input) input tokens.",
                sessionIDs: [context.session.id], responseIDs: point.responseID.map { [$0] } ?? []
            )], inference: [DiagnosticEvidenceItem(
                source: "specification_core_policy",
                detail: "HasUncachedBurstSpec satisfied the configured absolute and ratio thresholds.",
                sessionIDs: [context.session.id]
            )]), confidence: .high, coverage: .observed,
            affectedSessions: [context.session.id],
            suggestedNextAction: "Inspect the request context and any nearby compaction or model-boundary evidence."
        )
    }
}
