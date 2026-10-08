import Foundation
import MonitorCore
import SpecificationCore

/// Each decision runs its ordered blockers and, when none applies, reports the alert with its evidence.
struct BurnRateDecision: DecisionSpec {
    typealias Context = LiveRuleContext
    typealias Result = LiveRuleOutcome

    func decide(_ context: LiveRuleContext) -> LiveRuleOutcome? {
        if let blocked = LiveRuleBlockers.burn(context.configuration).decide(context) { return blocked }
        guard let reference = context.burnReference, let threshold = context.burnThreshold else { return .quiet }
        let configuration = context.configuration
        let recent = context.burnRequests
        let total = Double(LiveRuleSupport.saturatingSum(context.burnKnownInputs))
        let window = LiveRuleText.minutes(configuration.burnWindow)
        return .alert(AlertCandidate(
            key: "live|burn_rate|\(context.sessionID)", scope: LiveRules.scope("burn_rate", context.sessionID),
            source: .liveRule, kind: "burn_rate", severity: .warning, title: "Input burn rate above your usual",
            message: "This session consumed \(LiveRuleText.tokens(context.burnRate)) input tokens/min over the last "
                + "\(window), above \(LiveRuleText.tokens(threshold))/min "
                + "(\(LiveRuleText.factor(configuration.burnMultiplier)) your usual busy pace). "
                + "Next: check whether the agent is looping or re-reading large context.",
            sessionIDs: [context.sessionID],
            evidence: DiagnosticEvidence(
                observed: [LiveRuleText.requestEvidence(
                    recent, "\(recent.count) requests, \(LiveRuleText.tokens(total)) input tokens in \(window).",
                    context.sessionID
                )],
                inference: [DiagnosticEvidenceItem(
                    source: "own_history",
                    detail: "90th percentile of \(context.baseline.bucketRates.count) active \(window) intervals is "
                        + "\(LiveRuleText.tokens(reference)) tokens/min."
                )],
                limitations: ["Input volume includes cached input; it measures pace, not cost or waste."]
            )
        ))
    }
}

struct RunawayLoopDecision: DecisionSpec {
    typealias Context = LiveRuleContext
    typealias Result = LiveRuleOutcome

    func decide(_ context: LiveRuleContext) -> LiveRuleOutcome? {
        if let blocked = LiveRuleBlockers.loop(context.configuration).decide(context) { return blocked }
        guard let reference = context.loopReference, let threshold = context.loopThreshold else { return .quiet }
        let stretch = context.stretchRequests
        return .alert(AlertCandidate(
            key: "live|runaway_loop|\(context.sessionID)", scope: LiveRules.scope("runaway_loop", context.sessionID),
            source: .liveRule, kind: "runaway_loop", severity: .warning,
            title: "Many requests since the last human turn",
            message: "\(stretch.count) requests ran since the last human turn; your longest usual turns take "
                + "about \(reference). Next: check whether the agent is stuck and needs a prompt.",
            sessionIDs: [context.sessionID],
            evidence: DiagnosticEvidence(
                observed: [LiveRuleText.requestEvidence(
                    Array(stretch.suffix(10)), "\(stretch.count) usage requests after the latest human or goal turn.",
                    context.sessionID
                )],
                inference: [DiagnosticEvidenceItem(
                    source: "own_history",
                    detail: "90th percentile of \(context.baseline.stretchLengths.count) completed turns is "
                        + "\(reference) requests; threshold is \(Int(threshold.rounded(.up)))."
                )],
                limitations: ["A goal continuation counts as a turn boundary; long deliberate runs can look the same."]
            )
        ))
    }
}

struct InputGrowthDecision: DecisionSpec {
    typealias Context = LiveRuleContext
    typealias Result = LiveRuleOutcome

    func decide(_ context: LiveRuleContext) -> LiveRuleOutcome? {
        if let blocked = LiveRuleBlockers.growth(context.configuration).decide(context) { return blocked }
        let inputs = context.growthInputs
        guard let first = inputs.first, let last = inputs.last, let usual = context.growthReference else {
            return .quiet
        }
        let sizes = inputs.map { LiveRuleText.tokens(Double($0)) }.joined(separator: ", ")
        return .alert(AlertCandidate(
            key: "live|input_growth|\(context.sessionID)", scope: LiveRules.scope("input_growth", context.sessionID),
            source: .liveRule, kind: "input_growth", severity: .info, title: "Request input keeps growing",
            message: "Input grew from \(LiveRuleText.tokens(Double(first))) to \(LiveRuleText.tokens(Double(last))) "
                + "tokens over the last \(inputs.count) requests without a compaction, reaching your usual "
                + "large-request size. Next: consider compacting or starting a fresh session.",
            sessionIDs: [context.sessionID],
            evidence: DiagnosticEvidence(
                observed: [LiveRuleText.requestEvidence(
                    context.growthWindow, "Input per request: \(sizes).", context.sessionID
                )],
                inference: [DiagnosticEvidenceItem(
                    source: "own_history",
                    detail: "90th percentile of \(context.baseline.requestInputs.count) historical requests is "
                        + "\(LiveRuleText.tokens(Double(usual)))."
                )],
                limitations: ["Growth can be legitimate; this is a prompt to consider compaction, not proof of waste."]
            )
        ))
    }
}
