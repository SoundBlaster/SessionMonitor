import Foundation
import MonitorCore

/// Typed observations for the compact signal cards. Never parse diagnostic prose into numbers.
struct ContextInsightCardPresentation: Identifiable, Sendable {
    struct Metric: Identifiable, Sendable {
        let title: LocalizedStringResource
        let value: String
        let id: String
    }

    let insight: ContextInsight
    let title: LocalizedStringResource
    let metrics: [Metric]
    var id: String { insight.id }

    init(insight: ContextInsight, step: ContextAnatomyStep, previous: ContextAnatomyStep?) {
        self.insight = insight
        switch insight.kind {
        case .contextGrowth, .contextDrop:
            title = insight.kind == .contextGrowth ? "Context growth" : "Context drop"
            metrics = [
                Metric(title: "Previous input", value: Self.tokens(previous?.contextTokens), id: "before"),
                Metric(title: "Current input", value: Self.tokens(step.contextTokens), id: "after")
            ]
        case .compaction:
            title = "Context compacted"
            metrics = [Metric(title: "Explicit events", value: step.activityBefore.compactions.formatted(),
                              id: "events"),
                       Metric(title: "Current input", value: Self.tokens(step.contextTokens), id: "input")]
        case .coldStart:
            title = "Cold-start candidate"
            metrics = [Metric(title: "Cached share", value: Self.cacheShare(step), id: "cache"),
                       Metric(title: "Input tokens", value: Self.tokens(step.contextTokens), id: "input")]
        case .cacheDropAfterPause:
            title = "Cache drop after pause"
            metrics = [Metric(title: "Previous cache", value: Self.cacheShare(previous), id: "before"),
                       Metric(title: "Current cache", value: Self.cacheShare(step), id: "after"),
                       Metric(title: "Pause", value: previous.map {
                           let seconds = step.timestamp.timeIntervalSince($0.timestamp)
                           return Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds],
                                                                            width: .abbreviated, maximumUnitCount: 2))
                       } ?? "Unknown", id: "pause")]
        case .criticalEntry:
            title = "Entered critical zone"
            metrics = [Metric(title: "Window used", value: step.fillFraction.formatted(.percent), id: "fill"),
                       Metric(title: "Reported window", value: Self.tokens(step.contextWindowTokens), id: "window")]
        }
    }

    private static func tokens(_ value: Int64?) -> String {
        value.map(ContextAnatomyPresentation.compactTokens) ?? "Unknown"
    }

    private static func cacheShare(_ step: ContextAnatomyStep?) -> String {
        guard let step, step.contextTokens > 0, let cached = step.cachedInputTokens,
              cached >= 0, cached <= step.contextTokens else { return "Unknown" }
        return (Double(cached) / Double(step.contextTokens)).formatted(.percent.precision(.fractionLength(0...1)))
    }
}
