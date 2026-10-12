import Foundation
import MonitorCore

/// Pure presentation rules for the context-anatomy chart; the views only draw what this returns.
enum ContextAnatomyPresentation {
    static let hint = "Hover a request, or focus the chart and use the arrow keys, to see a snapshot of the context"
    static let inspectionHint = "No request inspected. Use the arrow keys or adjust to step through requests."
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

    /// Ticks for a zoomed window (SM-722): multiples of one stride, so labels stay put while panning; the
    /// first request stays labelled whenever the window starts at it.
    static func xTicks(in window: ClosedRange<Double>, stepCount: Int) -> [Int] {
        let first = max(1, Int(window.lowerBound.rounded(.up)))
        let last = min(stepCount, Int(window.upperBound.rounded(.down)))
        guard stepCount > 0, first <= last else { return [] }
        // The stride follows the window's span, not how many whole requests it encloses, so a pan never
        // changes it.
        let span = window.upperBound - window.lowerBound
        let stride = max(1, Int((span / Double(maxTickCount)).rounded(.up)))
        let start = stride == 1 ? first : Int((Double(first) / Double(stride)).rounded(.up)) * stride
        var ticks = Array(Swift.stride(from: start, through: last, by: stride))
        if first == 1, ticks.first != 1, stride > 1 { ticks.insert(1, at: 0) }
        return ticks
    }

    /// Names the visible requests when the window hides part of the session, with the navigation gestures.
    static func windowLabel(for window: ClosedRange<Double>, stepCount: Int) -> String? {
        let first = max(1, Int(window.lowerBound.rounded(.up)))
        let last = min(stepCount, Int(window.upperBound.rounded(.down)))
        guard stepCount > 0, first > 1 || last < stepCount else { return nil }
        return "Requests \(first)–\(last) of \(stepCount) · pinch or ⌘-scroll to zoom, scroll sideways or drag to move"
    }

    // MARK: Snapshot card

    /// Wide enough for the longest snapshot line (context share, zone and delta) on one line.
    static let snapshotCardWidth = 340.0
    static let snapshotCardMinWidth = 160.0
    static let snapshotCardGap = 12.0

    enum SnapshotCardSide: Equatable {
        case right
        case left
    }

    struct SnapshotCardPlacement: Equatable {
        let side: SnapshotCardSide
        let width: Double
    }

    /// Side of the inspected request's rule the floating card sits on, and the width it gets there.
    /// Right is preferred; the card flips left when only the left side holds it, and in a narrow plot it
    /// shrinks into the roomier side (never below `snapshotCardMinWidth`). `anchorX` is the rule's x
    /// inside the plot area.
    static func snapshotCardPlacement(anchorX: Double, plotWidth: Double) -> SnapshotCardPlacement {
        guard anchorX.isFinite, plotWidth.isFinite, plotWidth > 0 else {
            return SnapshotCardPlacement(side: .right, width: snapshotCardMinWidth)
        }
        let rightRoom = plotWidth - anchorX - snapshotCardGap
        let leftRoom = anchorX - snapshotCardGap
        if rightRoom >= snapshotCardWidth { return SnapshotCardPlacement(side: .right, width: snapshotCardWidth) }
        if leftRoom >= snapshotCardWidth { return SnapshotCardPlacement(side: .left, width: snapshotCardWidth) }
        let side: SnapshotCardSide = rightRoom >= leftRoom ? .right : .left
        let room = max(rightRoom, leftRoom)
        return SnapshotCardPlacement(side: side, width: max(snapshotCardMinWidth, min(snapshotCardWidth, room)))
    }

    // MARK: Inspection without a pointer

    /// Keyboard and VoiceOver stepping. The first step starts at an edge (forward from request 1, backward from the
    /// last request); later steps clamp to the session's requests. Nil when there is nothing to inspect.
    static func steppedIndex(from current: Int?, by delta: Int, stepCount: Int) -> Int? {
        guard stepCount > 0 else { return nil }
        guard let current else { return delta == 0 ? nil : (delta > 0 ? 1 : stepCount) }
        return min(stepCount, max(1, current + delta))
    }

    /// What VoiceOver reads for the always-present snapshot element: the card's lines, or how to start inspecting.
    static func snapshotAccessibilityValue(for step: ContextAnatomyStep?, in anatomy: ContextAnatomy,
                                           timeZone: TimeZone) -> String {
        guard let step else { return inspectionHint }
        return snapshotLines(for: step, in: anatomy, timeZone: timeZone).joined(separator: ". ")
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
