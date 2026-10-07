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

/// One session's evidence, ordered once, for the specifications that judge it.
struct LiveRuleContext {
    let timeline: RequestTimeline
    /// Every point of the session in time order.
    let points: [RequestTimelinePoint]
    /// The usage requests among `points`.
    let requests: [RequestTimelinePoint]
    let baseline: LiveBaseline
    let now: Date
    let configuration: LiveRuleConfiguration

    var sessionID: String { timeline.sessionID }

    init(timeline: RequestTimeline, baseline: LiveBaseline, now: Date, configuration: LiveRuleConfiguration) {
        self.timeline = timeline
        points = LiveRuleSupport.ordered(timeline)
        requests = points.filter { $0.kind == .usageRequest }
        self.baseline = baseline
        self.now = now
        self.configuration = configuration
    }
}

/// Live rules for running sessions. Every rule compares with the user's own history, reports its
/// evidence and coverage, and stays silent when the data it needs is unknown.
public enum LiveRules {
    public static let kinds = ["burn_rate", "runaway_loop", "input_growth"]

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
        let context = LiveRuleContext(timeline: timeline, baseline: baseline, now: now, configuration: configuration)
        return [
            ("burn_rate", BurnRateDecision().decide(context) ?? .quiet),
            ("runaway_loop", RunawayLoopDecision().decide(context) ?? .quiet),
            ("input_growth", InputGrowthDecision().decide(context) ?? .quiet)
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
