import Foundation
import MonitorCore

/// Bounded presentation only. The source timeline and its accounting remain unchanged.
enum RequestTimelineChartLayout {
    static let chartHeight: CGFloat = 250
    static let yAxisTopInset: CGFloat = 16
    static let barWidth: CGFloat = 4
    static let eventSymbolSize: CGFloat = 12
    static let maxChartPoints = 256
    static let reservedEventPoints = 64
    static let accessibilityLabel = "Cached and uncached input over time"

    static func chartPoints(
        from points: [RequestTimelinePoint], visibleDomain: DateInterval? = nil
    ) -> [RequestTimelinePoint] {
        let visible = points.filter { visibleDomain?.contains($0.timestamp) ?? true }
            .sorted(by: chronological)
        guard visible.count > maxChartPoints else { return visible }
        let usage = visible.filter { $0.kind == .usageRequest }
        let events = visible.filter { $0.kind != .usageRequest }
        let usageLimit = maxChartPoints - min(reservedEventPoints, events.count)
        let sampledUsage = sample(usage, limit: usageLimit)
        let eventLimit = maxChartPoints - sampledUsage.count
        let kinds = TimelineEventKind.allCases.filter { kind in events.contains { $0.kind == kind } }
        let perKindLimit = eventLimit / max(1, kinds.count)
        let sampledEvents = kinds.flatMap { kind in
            sample(events.filter { $0.kind == kind }, limit: perKindLimit)
        }
        return (sampledUsage + sampledEvents).sorted(by: chronological)
    }

    /// Preserve endpoints and token peaks, then sample across the remaining requests.
    private static func sample(_ points: [RequestTimelinePoint], limit: Int) -> [RequestTimelinePoint] {
        guard points.count > limit else { return points }
        guard limit > 0 else { return [] }
        var selected: Set<Int> = [0, points.count - 1]
        if let peak = points.indices.max(by: {
            (points[$0].cachedInputTokens ?? 0) < (points[$1].cachedInputTokens ?? 0)
        }) { selected.insert(peak) }
        if let peak = points.indices.max(by: {
            (points[$0].uncachedInputTokens ?? 0) < (points[$1].uncachedInputTokens ?? 0)
        }) { selected.insert(peak) }
        let candidates = points.indices.filter { !selected.contains($0) }
        let slots = max(0, limit - selected.count)
        for slot in 0..<slots {
            selected.insert(candidates[slot * candidates.count / slots])
        }
        return selected.sorted().prefix(limit).map { points[$0] }
    }

    private static func chronological(_ lhs: RequestTimelinePoint, _ rhs: RequestTimelinePoint) -> Bool {
        lhs.timestamp == rhs.timestamp ? lhs.id < rhs.id : lhs.timestamp < rhs.timestamp
    }
}
