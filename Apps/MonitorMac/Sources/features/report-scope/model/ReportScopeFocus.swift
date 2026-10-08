import Foundation
import MonitorCore

/// Pure rules for a temporary interval inside a report period.
enum ReportScopeFocus {
    /// The part of `interval` that lies inside the period of `query`; `nil` when they do not overlap.
    static func clipped(_ interval: DateInterval, to query: UsageQuery) -> DateInterval? {
        let since = max(query.since ?? .distantPast, interval.start)
        let until = min(query.until ?? .distantFuture, interval.end)
        return since < until ? DateInterval(start: since, end: until) : nil
    }

    /// `query` narrowed to `interval`; `query` itself when the narrowed query would be invalid.
    static func narrowed(_ query: UsageQuery, to interval: DateInterval) -> UsageQuery {
        (try? UsageQuery(since: interval.start, until: interval.end,
                         timeZoneIdentifier: query.timeZoneIdentifier, accountScope: query.accountScope)) ?? query
    }

    static func isInside(_ interval: DateInterval, of query: UsageQuery) -> Bool {
        interval.start >= (query.since ?? .distantPast) && interval.end <= (query.until ?? .distantFuture)
    }
}
