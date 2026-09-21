import Foundation
import MonitorCore

struct TimelineEventCount: Identifiable {
    let kind: TimelineEventKind
    let count: Int

    var id: TimelineEventKind { kind }
}

/// Prepared once per timeline load so viewport changes can query only visible points.
struct TimelinePointIndex {
    let points: [RequestTimelinePoint]
    let dataBounds: DateInterval?
    private let eventTimestampsByKind: [TimelineEventKind: [Date]]

    init(points: [RequestTimelinePoint]) {
        let orderedPoints: [RequestTimelinePoint]
        if Self.isOrdered(points) {
            orderedPoints = points
        } else {
            orderedPoints = points.sorted {
                if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
                return $0.id < $1.id
            }
        }
        self.points = orderedPoints
        if let first = orderedPoints.first, let last = orderedPoints.last {
            dataBounds = DateInterval(start: first.timestamp, end: last.timestamp)
        } else {
            dataBounds = nil
        }

        var timestampsByKind: [TimelineEventKind: [Date]] = [:]
        for point in orderedPoints where point.kind != .usageRequest {
            timestampsByKind[point.kind, default: []].append(point.timestamp)
        }
        eventTimestampsByKind = timestampsByKind
    }

    func points(in interval: DateInterval) -> ArraySlice<RequestTimelinePoint> {
        let start = lowerBound(in: points, for: interval.start)
        let end = upperBound(in: points, for: interval.end)
        return points[start..<max(start, end)]
    }

    func eventCounts(in interval: DateInterval) -> [TimelineEventCount] {
        TimelineEventKind.allCases.compactMap { kind in
            guard let timestamps = eventTimestampsByKind[kind] else { return nil }
            let start = lowerBound(in: timestamps, for: interval.start)
            let end = upperBound(in: timestamps, for: interval.end)
            let count = end - start
            return count > 0 ? TimelineEventCount(kind: kind, count: count) : nil
        }
    }

    private static func isOrdered(_ points: [RequestTimelinePoint]) -> Bool {
        zip(points, points.dropFirst()).allSatisfy { previous, next in
            if previous.timestamp != next.timestamp { return previous.timestamp < next.timestamp }
            return previous.id <= next.id
        }
    }

    private func lowerBound(in values: [RequestTimelinePoint], for date: Date) -> Int {
        var lower = 0
        var upper = values.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if values[middle].timestamp < date {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private func upperBound(in values: [RequestTimelinePoint], for date: Date) -> Int {
        var lower = 0
        var upper = values.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if values[middle].timestamp <= date {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private func lowerBound(in values: [Date], for date: Date) -> Int {
        var lower = 0
        var upper = values.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if values[middle] < date {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private func upperBound(in values: [Date], for date: Date) -> Int {
        var lower = 0
        var upper = values.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if values[middle] <= date {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }
}
