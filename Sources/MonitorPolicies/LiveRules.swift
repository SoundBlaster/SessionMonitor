import Foundation
import MonitorCore
import SpecificationCore

/// What one live rule concluded for one session. `unknown` never alerts and leaves existing alerts of
/// that rule untouched; only a clear negative (`quiet`) lets them resolve.
enum LiveRuleOutcome: Equatable {
    case alert(AlertCandidate)
    case quiet
    case unknown(String)
}

struct LiveRuleContext {
    let timeline: RequestTimeline
    let requests: [RequestTimelinePoint]
    let baseline: LiveBaseline
    let now: Date
    let configuration: LiveRuleConfiguration

    var sessionID: String { timeline.sessionID }
}

/// Only sessions with a request inside the live window are judged; finished work is history.
struct IsLiveSessionSpec: Specification {
    func isSatisfiedBy(_ context: LiveRuleContext) -> Bool {
        guard let newest = context.requests.last?.timestamp else { return false }
        let age = context.now.timeIntervalSince(newest)
        return age >= 0 && age <= context.configuration.liveWindow
    }
}

struct BurnRateRule {
    func outcome(_ context: LiveRuleContext) -> LiveRuleOutcome {
        let configuration = context.configuration
        guard IsLiveSessionSpec().isSatisfiedBy(context) else { return .quiet }
        let start = context.now.addingTimeInterval(-configuration.burnWindow)
        let recent = context.requests.filter { $0.timestamp > start && $0.timestamp <= context.now }
        guard recent.count >= configuration.minimumBurnRequests else { return .quiet }
        let known = recent.compactMap(LiveRuleSupport.input)
        guard known.count == recent.count else {
            return .unknown("Input tokens are unknown for some requests in the recent window.")
        }
        let rates = context.baseline.bucketRates
        guard rates.count >= configuration.minimumBaselineBuckets,
              let reference = LiveBaseline.percentile(rates, 0.9), reference > 0 else {
            return .unknown("Fewer than \(configuration.minimumBaselineBuckets) active historical intervals.")
        }
        let total = LiveRuleSupport.saturatingSum(known)
        let rate = Double(total) / (configuration.burnWindow / 60)
        let threshold = reference * configuration.burnMultiplier
        guard rate > threshold else { return .quiet }
        let window = LiveRuleText.minutes(configuration.burnWindow)
        return .alert(AlertCandidate(
            key: "live|burn_rate|\(context.sessionID)", scope: LiveRules.scope("burn_rate", context.sessionID),
            source: .liveRule, kind: "burn_rate", severity: .warning, title: "Input burn rate above your usual",
            message: "This session consumed \(LiveRuleText.tokens(rate)) input tokens/min over the last \(window), "
                + "above \(LiveRuleText.tokens(threshold))/min (\(LiveRuleText.factor(configuration.burnMultiplier)) "
                + "your usual busy pace). Next: check whether the agent is looping or re-reading large context.",
            sessionIDs: [context.sessionID],
            evidence: DiagnosticEvidence(
                observed: [LiveRuleText.requestEvidence(
                    recent,
                    "\(recent.count) requests, \(LiveRuleText.tokens(Double(total))) input tokens in \(window).",
                    context.sessionID
                )],
                inference: [DiagnosticEvidenceItem(
                    source: "own_history",
                    detail: "90th percentile of \(rates.count) active \(window) intervals is "
                        + "\(LiveRuleText.tokens(reference)) tokens/min."
                )],
                limitations: ["Input volume includes cached input; it measures pace, not cost or waste."]
            )
        ))
    }
}

struct RunawayLoopRule {
    func outcome(_ context: LiveRuleContext) -> LiveRuleOutcome {
        let configuration = context.configuration
        guard IsLiveSessionSpec().isSatisfiedBy(context) else { return .quiet }
        let points = LiveRuleSupport.ordered(context.timeline)
        guard let boundary = points.lastIndex(where: { $0.kind == .humanTurn || $0.kind == .goalTurn }) else {
            return .unknown("No human turn is inside the evaluated window.")
        }
        let stretch = points[(boundary + 1)...].filter { $0.kind == .usageRequest }
        let lengths = context.baseline.stretchLengths
        guard lengths.count >= configuration.minimumBaselineStretches,
              let reference = LiveBaseline.percentile(lengths, 0.9) else {
            return .unknown("Fewer than \(configuration.minimumBaselineStretches) completed historical turns.")
        }
        let threshold = max(
            Double(configuration.minimumLoopRequests), Double(reference) * configuration.loopMultiplier
        )
        guard Double(stretch.count) > threshold else { return .quiet }
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
                    detail: "90th percentile of \(lengths.count) completed turns is \(reference) requests; "
                        + "threshold is \(Int(threshold.rounded(.up)))."
                )],
                limitations: ["A goal continuation counts as a turn boundary; long deliberate runs can look the same."]
            )
        ))
    }
}

struct InputGrowthRule {
    func outcome(_ context: LiveRuleContext) -> LiveRuleOutcome {
        let configuration = context.configuration
        guard IsLiveSessionSpec().isSatisfiedBy(context) else { return .quiet }
        var sinceCompaction: [RequestTimelinePoint] = []
        for point in LiveRuleSupport.ordered(context.timeline) {
            if point.kind == .compaction { sinceCompaction = [] }
            if point.kind == .usageRequest { sinceCompaction.append(point) }
        }
        let recent = Array(sinceCompaction.suffix(configuration.growthRequests))
        guard recent.count == configuration.growthRequests else { return .quiet }
        let known = recent.compactMap(LiveRuleSupport.input)
        guard known.count == recent.count else { return .unknown("Input tokens are unknown for some recent requests.") }
        guard let first = known.first, let last = known.last, first > 0,
              zip(known, known.dropFirst()).allSatisfy({ $0 <= $1 }),
              Double(last) >= Double(first) * configuration.growthRatio else { return .quiet }
        let history = context.baseline.requestInputs
        guard history.count >= configuration.minimumBaselineRequests,
              let usual = LiveBaseline.percentile(history, 0.9) else {
            return .unknown("Fewer than \(configuration.minimumBaselineRequests) historical requests.")
        }
        guard last >= usual else { return .quiet }
        let sizes = known.map { LiveRuleText.tokens(Double($0)) }.joined(separator: ", ")
        return .alert(AlertCandidate(
            key: "live|input_growth|\(context.sessionID)", scope: LiveRules.scope("input_growth", context.sessionID),
            source: .liveRule, kind: "input_growth", severity: .info, title: "Request input keeps growing",
            message: "Input grew from \(LiveRuleText.tokens(Double(first))) to \(LiveRuleText.tokens(Double(last))) "
                + "tokens over the last \(known.count) requests without a compaction, reaching your usual "
                + "large-request size. Next: consider compacting or starting a fresh session.",
            sessionIDs: [context.sessionID],
            evidence: DiagnosticEvidence(
                observed: [LiveRuleText.requestEvidence(
                    recent, "Input per request: \(sizes).",
                    context.sessionID
                )],
                inference: [DiagnosticEvidenceItem(
                    source: "own_history",
                    detail: "90th percentile of \(history.count) historical requests is "
                        + "\(LiveRuleText.tokens(Double(usual)))."
                )],
                limitations: ["Growth can be legitimate; this is a prompt to consider compaction, not proof of waste."]
            )
        ))
    }
}

/// Live rules for running sessions. Every rule compares with the user's own history, reports its
/// evidence and coverage, and stays silent when the data it needs is unknown.
public enum LiveRules {
    public static let kinds = ["burn_rate", "runaway_loop", "input_growth"]
    public static let quotaProjectionScope = AlertScope("quota:projection")

    /// One scope per rule and session, so a finished session's alerts resolve without touching others.
    public static func scope(_ kind: String, _ sessionID: String) -> AlertScope {
        AlertScope("live:\(kind):session:\(sessionID)")
    }

    public static func sessionSignals(
        timelines: [RequestTimeline], baseline: LiveBaseline, now: Date,
        configuration: LiveRuleConfiguration = .init()
    ) -> AlertSignalBatch {
        var batch = AlertSignalBatch()
        for timeline in timelines {
            for (kind, outcome) in outcomes(timeline, baseline: baseline, now: now, configuration: configuration) {
                switch outcome {
                case let .alert(candidate):
                    batch.scopes.insert(scope(kind, timeline.sessionID))
                    batch.candidates.append(candidate)
                case .quiet:
                    batch.scopes.insert(scope(kind, timeline.sessionID))
                case .unknown:
                    break
                }
            }
        }
        return batch
    }

    static func outcomes(
        _ timeline: RequestTimeline, baseline: LiveBaseline, now: Date, configuration: LiveRuleConfiguration
    ) -> [(String, LiveRuleOutcome)] {
        let context = LiveRuleContext(
            timeline: timeline, requests: LiveRuleSupport.requests(timeline), baseline: baseline, now: now,
            configuration: configuration
        )
        return [
            ("burn_rate", BurnRateRule().outcome(context)),
            ("runaway_loop", RunawayLoopRule().outcome(context)),
            ("input_growth", InputGrowthRule().outcome(context))
        ]
    }
}

enum LiveRuleText {
    static func tokens(_ value: Double) -> String {
        switch value {
        case 1_000_000...: String(format: "%.1fM", value / 1_000_000)
        case 1_000...: String(format: "%.1fk", value / 1_000)
        default: String(format: "%.0f", value)
        }
    }

    static func minutes(_ seconds: TimeInterval) -> String { "\(Int((seconds / 60).rounded())) min" }

    static func factor(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))×" : String(format: "%.1f×", value)
    }

    static func requestEvidence(_ points: [RequestTimelinePoint], _ detail: String, _ sessionID: String)
        -> DiagnosticEvidenceItem {
        DiagnosticEvidenceItem(
            source: "request_timeline", detail: detail, sessionIDs: [sessionID],
            responseIDs: points.compactMap(\.responseID), sourceLines: points.compactMap(\.sourceLine)
        )
    }
}
