import MonitorCore
import SpecificationCore

/// Pure, bounded pass over one timeline snapshot. No viewport, UI or wall-clock state enters the policy.
public enum ContextInsightPolicy {
    public static func evaluate(_ timeline: RequestTimeline,
                                configuration: ContextInsightConfiguration = .init()) -> ContextInsightReport {
        let points = timeline.points.filter { $0.sessionID == timeline.sessionID }
        let scoped = RequestTimeline(sessionID: timeline.sessionID, query: timeline.query, points: points)
        let anatomy = ContextAnatomyBuilder.build(scoped)
        let requests = points.filter { $0.kind == .usageRequest }
        var positions: [String: Int] = [:]
        for (index, point) in requests.enumerated() { positions[point.id] = index }
        let decisions: [AnyDecisionSpec<ContextInsightCandidate, ContextInsight>] = [
            AnyDecisionSpec(ContextCompactionDecision()),
            AnyDecisionSpec(ContextChangeDecision(configuration: configuration)),
            AnyDecisionSpec(ContextColdStartDecision(configuration: configuration)),
            AnyDecisionSpec(ContextCachePauseDecision(configuration: configuration)),
            AnyDecisionSpec(ContextCriticalEntryDecision())
        ]
        var insights: [ContextInsight] = []
        var previous: ContextAnatomyStep?
        for step in anatomy.steps {
            let position = positions[step.id]
            let previousPosition = previous.flatMap { positions[$0.id] }
            let adjacent = position.flatMap { current in previousPosition.map { current == $0 + 1 } } ?? false
            let candidate = ContextInsightCandidate(
                step: step, previous: previous, adjacent: adjacent,
                isFirstObservedRequest: position == 0, sessionID: timeline.sessionID
            )
            // Evaluate every independent signal: recovery/compaction must never hide an earlier drop.
            insights.append(contentsOf: decisions.compactMap { $0.decide(candidate) })
            previous = step
        }
        return ContextInsightReport(query: timeline.query, anatomy: anatomy, insights: insights,
                                    phases: phases(anatomy.steps, positions: positions),
                                    limitations: limitations(anatomy, query: timeline.query))
    }

    private static func limitations(_ anatomy: ContextAnatomy, query: UsageQuery) -> [String] {
        var result = ["Signals describe the observed query only. No signal does not mean no anomaly."]
        if query.since != nil || query.until != nil {
            result.append("The selected period may omit the session start, earlier requests and trailing events.")
        }
        if anatomy.requestsWithUnknownInput > 0 {
            result.append("\(anatomy.requestsWithUnknownInput) request(s) have unknown input. "
                + "They are excluded from zone totals; pair rules never bridge them.")
        }
        if anatomy.steps.contains(where: { $0.cachedInputTokens == nil || $0.model?.isEmpty != false }) {
            result.append("Missing cache or model evidence prevents some cache/pair assessments.")
        }
        if anatomy.basis == .sessionPeak {
            result.append("Zone summaries use the session peak; critical-window entry cannot be assessed.")
        } else if anatomy.steps.contains(where: \.contextWindowInferred) {
            result.append("Some window sizes are inferred. Critical entry requires two explicit, equal windows.")
        }
        if anatomy.trailingActivity.compactions > 0 {
            result.append("\(anatomy.trailingActivity.compactions) trailing compaction event(s) "
                + "have no following request marker.")
        }
        return result
    }

    private static func phases(_ steps: [ContextAnatomyStep], positions: [String: Int]) -> [ContextInsightPhase] {
        var result: [ContextInsightPhase] = []
        var run: [ContextAnatomyStep] = []
        for step in steps {
            if let previous = run.last {
                let adjacent = positions[step.id].flatMap { current in
                    positions[previous.id].map { current == $0 + 1 }
                } ?? false
                if step.zone != previous.zone || !adjacent || step.model != previous.model
                    || step.contextWindowTokens != previous.contextWindowTokens {
                    result.append(phase(run))
                    run.removeAll(keepingCapacity: true)
                }
            }
            run.append(step)
        }
        if !run.isEmpty { result.append(phase(run)) }
        return result
    }

    private static func phase(_ steps: [ContextAnatomyStep]) -> ContextInsightPhase {
        // Called only for a non-empty contiguous run.
        let first = steps[0]
        let last = steps[steps.count - 1]
        return ContextInsightPhase(
            zone: first.zone, firstRequestID: first.id, firstIndex: first.index, lastIndex: last.index,
            requests: steps.count, inputTokens: sum(steps.map { Optional($0.contextTokens) }),
            outputTokens: sum(steps.map(\.outputTokens))
        )
    }

    private static func sum(_ values: [Int64?]) -> Int64? {
        values.reduce(Optional(Int64(0))) { total, value in
            guard let total, let value else { return nil }
            let (sum, overflow) = total.addingReportingOverflow(value)
            return overflow ? nil : sum
        }
    }
}
