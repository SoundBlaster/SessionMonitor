import Foundation
import MonitorCore
import SpecificationCore

/// All numerical thresholds belong to domain policy, never the chart.
public struct ContextInsightConfiguration: Sendable {
    public let minimumChangeTokens: Int64
    public let minimumChangeFraction: Double
    public let minimumCacheInput: Int64
    public let cacheDropFraction: Double
    public let coldCacheFraction: Double
    public let pauseSeconds: TimeInterval

    public init(minimumChangeTokens: Int64 = 8_000, minimumChangeFraction: Double = 0.25,
                minimumCacheInput: Int64 = 1_000, cacheDropFraction: Double = 0.5,
                coldCacheFraction: Double = 0.1, pauseSeconds: TimeInterval = 300) {
        self.minimumChangeTokens = max(1, minimumChangeTokens)
        self.minimumChangeFraction = Self.fraction(minimumChangeFraction, fallback: 0.25)
        self.minimumCacheInput = max(1, minimumCacheInput)
        self.cacheDropFraction = max(0.01, Self.fraction(cacheDropFraction, fallback: 0.5))
        self.coldCacheFraction = Self.fraction(coldCacheFraction, fallback: 0.1)
        self.pauseSeconds = pauseSeconds.isFinite ? max(1, pauseSeconds) : 300
    }

    private static func fraction(_ value: Double, fallback: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : fallback
    }
}

struct ContextInsightCandidate {
    let step: ContextAnatomyStep
    let previous: ContextAnatomyStep?
    let adjacent: Bool
    let isFirstObservedRequest: Bool
    let sessionID: String

    var comparable: Bool {
        guard adjacent, let previous, let model = step.model, !model.isEmpty,
              previous.model == model else { return false }
        let gap = step.timestamp.timeIntervalSince(previous.timestamp)
        return gap.isFinite && gap >= 0
    }

    var cacheRatio: Double? { Self.ratio(step) }
    var previousCacheRatio: Double? { previous.flatMap(Self.ratio) }

    private static func ratio(_ step: ContextAnatomyStep) -> Double? {
        guard step.contextTokens > 0, let cached = step.cachedInputTokens,
              cached >= 0, cached <= step.contextTokens else { return nil }
        return Double(cached) / Double(step.contextTokens)
    }

    func insight(_ kind: ContextInsightKind, title: String, reason: String,
                 hypothesis: Bool = false) -> ContextInsight {
        var observed = ["Request \(step.index): input \(step.contextTokens), cached "
            + "\(step.cachedInputTokens.map(String.init) ?? "unknown"), "
            + "explicit compactions before request \(step.activityBefore.compactions)."]
        if let previous {
            observed.append("Previous input \(previous.contextTokens), cached "
                + "\(previous.cachedInputTokens.map(String.init) ?? "unknown"); "
                + "gap \(step.timestamp.timeIntervalSince(previous.timestamp)) seconds.")
        }
        if let window = step.contextWindowTokens {
            observed.append("Context window \(window), inferred: \(step.contextWindowInferred).")
        }
        return ContextInsight(
            kind: kind, step: step, title: title, explanation: reason,
            evidence: DiagnosticEvidence(
                observed: observed.map {
                    DiagnosticEvidenceItem(source: "request_timeline", detail: $0, sessionIDs: [sessionID])
                },
                inference: hypothesis ? [DiagnosticEvidenceItem(
                    source: "context_insight_policy", detail: reason, sessionIDs: [sessionID])] : [],
                limitations: ["Observed query range only; request volumes do not reveal context contents."]
            ), isHypothesis: hypothesis
        )
    }
}

struct ComparableContextRequestsSpec: Specification {
    func isSatisfiedBy(_ candidate: ContextInsightCandidate) -> Bool { candidate.comparable }
}

struct SignificantContextChangeSpec: Specification {
    let configuration: ContextInsightConfiguration

    func isSatisfiedBy(_ candidate: ContextInsightCandidate) -> Bool {
        guard let previous = candidate.previous else { return false }
        let change = abs(Double(candidate.step.contextTokens) - Double(previous.contextTokens))
        return change >= Double(configuration.minimumChangeTokens)
            && change / Double(max(1, previous.contextTokens)) >= configuration.minimumChangeFraction
    }
}

struct ContextChangeDecision: DecisionSpec {
    let configuration: ContextInsightConfiguration

    func decide(_ context: ContextInsightCandidate) -> ContextInsight? {
        let rule = ComparableContextRequestsSpec().and(SignificantContextChangeSpec(configuration: configuration))
        guard rule.isSatisfiedBy(context), let previous = context.previous else { return nil }
        if context.step.contextTokens > previous.contextTokens {
            return context.insight(.contextGrowth, title: "Context jump", reason:
                "Input grew by at least \(configuration.minimumChangeTokens) tokens and "
                + "\(Int(configuration.minimumChangeFraction * 100))% versus the previous comparable request.")
        }
        return context.insight(.contextDrop, title: "Context drop", reason:
            context.step.activityBefore.compactions > 0
                ? "Input shrank and an explicit compaction was observed between these requests."
                : "Input shrank. No explicit compaction was observed; the cause is unknown and a reset is not proven.")
    }
}

struct ContextCompactionDecision: DecisionSpec {
    func decide(_ context: ContextInsightCandidate) -> ContextInsight? {
        guard context.step.activityBefore.compactions > 0 else { return nil }
        return context.insight(.compaction, title: "Compaction observed", reason:
            "The source reports \(context.step.activityBefore.compactions) compaction event(s) before this request. "
            + "This does not prove that compaction caused a particular token change.")
    }
}

struct ContextColdStartDecision: DecisionSpec {
    let configuration: ContextInsightConfiguration

    func decide(_ context: ContextInsightCandidate) -> ContextInsight? {
        guard context.isFirstObservedRequest, context.step.contextTokens >= configuration.minimumCacheInput,
              let ratio = context.cacheRatio, ratio <= configuration.coldCacheFraction else { return nil }
        return context.insight(.coldStart, title: "Cold-start candidate", reason:
            "The first observed request has little cached input. Earlier session history may be outside "
            + "this query; a true session start or cache expiry is not established.", hypothesis: true)
    }
}

struct ContextCachePauseDecision: DecisionSpec {
    let configuration: ContextInsightConfiguration

    func decide(_ context: ContextInsightCandidate) -> ContextInsight? {
        guard ComparableContextRequestsSpec().isSatisfiedBy(context), let previous = context.previous,
              previous.contextTokens >= configuration.minimumCacheInput,
              context.step.contextTokens >= configuration.minimumCacheInput,
              let before = context.previousCacheRatio, let after = context.cacheRatio,
              before - after >= configuration.cacheDropFraction,
              context.step.timestamp.timeIntervalSince(previous.timestamp) >= configuration.pauseSeconds else {
            return nil
        }
        return context.insight(.cacheDropAfterPause, title: "Cache drop after pause · hypothesis", reason:
            "Cache share fell by at least \(Int(configuration.cacheDropFraction * 100)) percentage points "
            + "after a pause of at least \(String(format: "%.0f", configuration.pauseSeconds)) seconds "
            + "on the same reported model. "
            + "Timing alone cannot establish cache expiry or its cause.", hypothesis: true)
    }
}

struct ContextCriticalEntryDecision: DecisionSpec {
    func decide(_ context: ContextInsightCandidate) -> ContextInsight? {
        guard ComparableContextRequestsSpec().isSatisfiedBy(context), let previous = context.previous,
              !previous.contextWindowInferred, !context.step.contextWindowInferred,
              previous.contextWindowTokens == context.step.contextWindowTokens,
              context.step.contextWindowTokens != nil,
              previous.zone != .critical, context.step.zone == .critical else { return nil }
        return context.insight(.criticalEntry, title: "Entered critical context zone", reason:
            "Input crossed 90% of the same explicitly reported usable context window. "
            + "This is context occupancy, not account quota or billed usage.")
    }
}
