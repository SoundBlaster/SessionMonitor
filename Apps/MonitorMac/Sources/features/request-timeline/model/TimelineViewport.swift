import Foundation

/// Navigation only: never modifies the query used to fetch canonical evidence.
enum TimelineViewport {
    static let minimumSpan: TimeInterval = 60

    static func clamp(_ range: DateInterval, to bounds: DateInterval) -> DateInterval {
        let span = min(bounds.duration, max(minimumSpan, range.duration))
        let start = min(max(bounds.start, range.start), bounds.end.addingTimeInterval(-span))
        return DateInterval(start: start, duration: span)
    }
}
