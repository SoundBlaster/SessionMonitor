import Foundation
import MonitorCore

/// Pure presentation rules for the context-anatomy chart; the views only draw what this returns.
enum ContextAnatomyPresentation {
    static let hint = "Hover a request to see a snapshot of the context at that point"
    static let caption = "Context size per request, relative to this session's peak. "
        + "Logs show token volumes and events, not what the context contains."
    static let maxTickCount = 12

    // MARK: Geometry

    /// Columns are centered on integer request indexes and are one unit wide.
    static func xDomain(stepCount: Int) -> ClosedRange<Double> {
        0.5...(Double(max(1, stepCount)) + 0.5)
    }

    static func yDomain(peak: Int64) -> ClosedRange<Double> {
        0...Double(max(1, peak))
    }

    /// Nearest 1-based request index for a chart x value, clamped to the range; nil without steps.
    static func stepIndex(forX value: Double, stepCount: Int) -> Int? {
        guard stepCount > 0, value.isFinite else { return nil }
        return min(stepCount, max(1, Int(value.rounded())))
    }

    /// Integer tick positions: every request for short sessions, an even stride otherwise.
    static func xTicks(stepCount: Int) -> [Int] {
        guard stepCount > 0 else { return [] }
        let stride = max(1, Int((Double(stepCount) / Double(maxTickCount)).rounded(.up)))
        var ticks = Array(Swift.stride(from: 1, through: stepCount, by: stride))
        if stride > 1, let last = ticks.last, stepCount - last >= stride / 2 + 1 { ticks.append(stepCount) }
        return ticks
    }

    // MARK: Text

    static func snapshotLines(for step: ContextAnatomyStep, in anatomy: ContextAnatomy,
                              timeZone: TimeZone) -> [String] {
        [
            headline(step, of: anatomy.steps.count, timeZone: timeZone),
            contextLine(step),
            cacheLine(step),
            outputLine(step),
            cumulativeLine(step),
            activityLine(step)
        ]
    }

    static func accessibilitySummary(_ anatomy: ContextAnatomy) -> String {
        let count = anatomy.steps.count
        guard let final = anatomy.steps.last else { return "Context anatomy: no requests with known input." }
        let compactions = anatomy.steps.reduce(anatomy.trailingActivity.compactions) {
            $0 + $1.activityBefore.compactions
        }
        var text = "Context anatomy: \(plural(count, "request")), "
            + "peak \(compactTokens(anatomy.peakContextTokens)) tokens, "
            + "final context \(compactTokens(final.contextTokens)) tokens, \(plural(compactions, "compaction"))."
        if anatomy.requestsWithUnknownInput > 0 {
            text += " \(plural(anatomy.requestsWithUnknownInput, "request")) skipped for unknown input."
        }
        return text
    }

    /// Compact deterministic token count: 950, 182.4k, 2.1M, 1.3B. Locale independent.
    static func compactTokens(_ value: Int64) -> String {
        let magnitude = Double(value.magnitude)
        let sign = value < 0 ? "-" : ""
        if magnitude < 1_000 { return "\(sign)\(value.magnitude)" }
        let units = [TokenUnit(scale: 1_000, suffix: "k"), TokenUnit(scale: 1_000_000, suffix: "M"),
                     TokenUnit(scale: 1_000_000_000, suffix: "B")]
        for unit in units {
            let scaled = (magnitude / unit.scale * 10).rounded() / 10
            if scaled < 1_000 || unit.suffix == "B" { return sign + String(format: "%.1f", scaled) + unit.suffix }
        }
        return sign + String(format: "%.1f", magnitude / 1_000_000_000) + "B"
    }

    private struct TokenUnit {
        let scale: Double
        let suffix: String
    }

    // MARK: Snapshot lines

    private static func headline(_ step: ContextAnatomyStep, of count: Int, timeZone: TimeZone) -> String {
        var parts = ["Request \(step.index) of \(count)", clockTime(step.timestamp, timeZone: timeZone)]
        if let model = step.model, !model.isEmpty { parts.append(model) }
        return parts.joined(separator: " · ")
    }

    private static func contextLine(_ step: ContextAnatomyStep) -> String {
        let percent = Int((step.fillFraction * 100).rounded())
        let change = step.deltaFromPrevious.map { "\(signedTokens($0)) vs previous" } ?? "first request"
        return "Context \(compactTokens(step.contextTokens)) (\(percent)% of peak, \(step.zone.rawValue)) · \(change)"
    }

    private static func cacheLine(_ step: ContextAnatomyStep) -> String {
        guard let cached = step.cachedInputTokens, let new = step.newInputTokens else { return "cache split unknown" }
        return "Cached \(compactTokens(cached)) · new \(compactTokens(new))"
    }

    private static func outputLine(_ step: ContextAnatomyStep) -> String {
        guard let output = step.outputTokens else { return "Output unknown" }
        let reasoning = step.reasoningOutputTokens.map(compactTokens) ?? "unknown"
        return "Output \(compactTokens(output)) (reasoning \(reasoning))"
    }

    private static func cumulativeLine(_ step: ContextAnatomyStep) -> String {
        guard let cumulative = step.cumulativeTokens else {
            return "cumulative unknown (a request has unknown output)"
        }
        return "Cumulative \(compactTokens(cumulative))"
    }

    private static func activityLine(_ step: ContextAnatomyStep) -> String {
        let activity = step.activityBefore
        let prefix = step.index == 1 ? "Before first request" : "Since previous request"
        let parts = [
            countPart(activity.tools, "tool"), countPart(activity.waits, "wait"),
            countPart(activity.humanTurns, "human turn"), countPart(activity.goalTurns, "goal turn"),
            activity.compactions == 1 ? "compaction" : countPart(activity.compactions, "compaction"),
            countPart(activity.other, "other event")
        ].compactMap { $0 }
        guard !parts.isEmpty else {
            return step.index == 1 ? "no events before first request" : "no events since previous request"
        }
        return "\(prefix): " + parts.joined(separator: ", ")
    }

    // MARK: Helpers

    private static func signedTokens(_ delta: Int64) -> String {
        delta < 0 ? "\u{2212}\(compactTokens(-delta))" : "+\(compactTokens(delta))"
    }

    private static func countPart(_ count: Int, _ noun: String) -> String? {
        count > 0 ? plural(count, noun) : nil
    }

    private static func plural(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    private static func clockTime(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        return String(format: "%02d:%02d:%02d", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }
}
