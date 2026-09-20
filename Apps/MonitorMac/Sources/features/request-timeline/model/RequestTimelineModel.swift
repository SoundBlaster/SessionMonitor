import Foundation
import MonitorCore
import Observation

protocol RequestTimelineSource: Sendable {
    func timeline(sessionID: String, query: UsageQuery) async throws -> RequestTimeline
}

enum RequestTimelineRangeMode: String, CaseIterable, Hashable, Identifiable {
    case fitToData
    case lastEvents
    case fullQuery
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fitToData: "Fit to data"
        case .lastEvents: "Last events"
        case .fullQuery: "Full query"
        case .custom: "Custom"
        }
    }
}

/// Separates the observed event span from the absolute query span used to read it.
/// Both are finite for charting, but only `visibleDomain` changes when the user navigates.
struct RequestTimelineAxis: Equatable {
    let dataBounds: DateInterval
    let dataDomain: DateInterval
    let queryDomain: DateInterval
    let visibleDomain: DateInterval
    let mode: RequestTimelineRangeMode
    let queryHasBound: Bool

    var navigationDomain: DateInterval {
        DateInterval(start: min(dataDomain.start, queryDomain.start), end: max(dataDomain.end, queryDomain.end))
    }

    init?(
        points: [RequestTimelinePoint], query: UsageQuery,
        mode: RequestTimelineRangeMode, recentWindow: TimeInterval = 15 * 60,
        customDomain: DateInterval? = nil
    ) {
        guard
            let first = points.map(\.timestamp).min(),
            let last = points.map(\.timestamp).max()
        else {
            return nil
        }
        let dataBounds = DateInterval(start: first, end: last)
        let dataDomain = Self.padded(dataBounds)
        let queryStart = query.since ?? dataDomain.start
        let queryEnd = query.until ?? dataDomain.end
        guard queryStart < queryEnd else { return nil }
        let queryDomain = DateInterval(start: queryStart, end: queryEnd)
        let visibleDomain: DateInterval
        switch mode {
        case .fitToData:
            visibleDomain = dataDomain
        case .lastEvents:
            let recentStart = max(dataBounds.start, dataBounds.end.addingTimeInterval(-recentWindow))
            visibleDomain = Self.padded(DateInterval(start: recentStart, end: dataBounds.end))
        case .custom:
            let bounds = DateInterval(start: min(dataDomain.start, queryDomain.start),
                                      end: max(dataDomain.end, queryDomain.end))
            visibleDomain = TimelineViewport.clamp(customDomain ?? dataDomain, to: bounds)
        case .fullQuery:
            visibleDomain = query.since == nil && query.until == nil ? dataDomain : queryDomain
        }

        self.dataBounds = dataBounds
        self.dataDomain = dataDomain
        self.queryDomain = queryDomain
        self.visibleDomain = visibleDomain
        self.mode = mode
        queryHasBound = query.since != nil || query.until != nil
    }

    func description(timeZone: TimeZone) -> String {
        let data = "\(timelineDateLabel(dataBounds.start, timeZone: timeZone))–"
            + "\(timelineDateLabel(dataBounds.end, timeZone: timeZone))"
        switch mode {
        case .fitToData:
            return "Fit to data: observed events span \(data). Query bounds remain available through Full query."
        case .lastEvents:
            let ending = timelineDateLabel(dataBounds.end, timeZone: timeZone)
            return "Last events: showing the trailing 15-minute window ending at \(ending)."
        case .custom:
            return "Custom range: \(timelineDateLabel(visibleDomain.start, timeZone: timeZone))–"
                + timelineDateLabel(visibleDomain.end, timeZone: timeZone)
        case .fullQuery:
            if queryHasBound {
                return "Full query: showing the selected absolute query range."
            }
            return "Full range: no finite query bounds; showing the observed data span."
        }
    }

    private static func padded(_ bounds: DateInterval) -> DateInterval {
        let padding = min(max(30, bounds.duration * 0.08), 5 * 60)
        return DateInterval(
            start: bounds.start.addingTimeInterval(-padding),
            end: bounds.end.addingTimeInterval(padding)
        )
    }
}

func timelineDateLabel(_ date: Date, timeZone: TimeZone) -> String {
    var format = Date.FormatStyle(date: .abbreviated, time: .shortened)
    format.timeZone = timeZone
    return date.formatted(format)
}

@MainActor
@Observable
final class RequestTimelineModel {
    private(set) var timeline: RequestTimeline?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    // A broad query must not manufacture empty chart canvas; Full query remains explicit.
    private(set) var customDomain: DateInterval?
    private(set) var rangeError: String?
    private(set) var rangeMode: RequestTimelineRangeMode = .fitToData

    var axis: RequestTimelineAxis? {
        guard let timeline else { return nil }
        return RequestTimelineAxis(points: timeline.points, query: timeline.query, mode: rangeMode,
                                   customDomain: customDomain)
    }

    var displayTimeZone: TimeZone {
        TimeZone(identifier: timeline?.query.timeZoneIdentifier ?? "UTC") ?? .gmt
    }

    var rangeDescription: String {
        axis?.description(timeZone: displayTimeZone) ?? "No timeline range selected."
    }

    func load(sessionID: String, query: UsageQuery, source: any RequestTimelineSource) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let value = try await source.timeline(sessionID: sessionID, query: query)
            guard value.sessionID == sessionID, value.query == query else {
                errorMessage = "Timeline query did not match the selected session."
                return
            }
            if timeline?.sessionID != value.sessionID || timeline?.query != value.query {
                rangeMode = .fitToData
                customDomain = nil
                rangeError = nil
            }
            timeline = value
        } catch {
            errorMessage = "Could not load request timeline. \(error.localizedDescription)"
        }
    }

    func setRangeMode(_ value: RequestTimelineRangeMode) {
        rangeMode = value
        rangeError = nil
    }

    func applyRange(from start: Date, to end: Date) {
        guard let axis else { return }
        guard start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite, start < end else {
            rangeError = "From must be earlier than To."
            return
        }
        guard start >= axis.navigationDomain.start, end <= axis.navigationDomain.end else {
            rangeError = "Choose a range within the timeline bounds."
            return
        }
        setViewport(DateInterval(start: start, end: end))
    }

    func zoom(by factor: Double) {
        guard let axis, factor.isFinite, factor > 0 else { return }
        let middle = axis.visibleDomain.start.addingTimeInterval(axis.visibleDomain.duration / 2)
        let span = min(axis.navigationDomain.duration,
                       max(TimelineViewport.minimumSpan, axis.visibleDomain.duration * factor))
        setViewport(DateInterval(start: middle.addingTimeInterval(-span / 2), duration: span))
    }

    func pan(by fraction: Double) {
        guard let axis, fraction.isFinite else { return }
        setViewport(DateInterval(start: axis.visibleDomain.start.addingTimeInterval(
            axis.visibleDomain.duration * fraction), duration: axis.visibleDomain.duration))
    }

    var scrollPosition: Double {
        guard let axis else { return 0 }
        let travel = axis.navigationDomain.duration - axis.visibleDomain.duration
        return travel > 0 ? (axis.visibleDomain.start.timeIntervalSince(axis.navigationDomain.start) / travel) : 0
    }

    func scroll(to fraction: Double) {
        guard let axis, fraction.isFinite else { return }
        let travel = max(0, axis.navigationDomain.duration - axis.visibleDomain.duration)
        setViewport(DateInterval(start: axis.navigationDomain.start.addingTimeInterval(
            travel * min(1, max(0, fraction))), duration: axis.visibleDomain.duration))
    }

    private func setViewport(_ range: DateInterval) {
        guard let axis else { return }
        customDomain = TimelineViewport.clamp(range, to: axis.navigationDomain)
        rangeMode = .custom
        rangeError = nil
    }

    func reset() {
        timeline = nil
        isLoading = false
        errorMessage = nil
        rangeMode = .fitToData
        customDomain = nil
        rangeError = nil
    }

    func fail(_ error: Error) {
        isLoading = false
        errorMessage = "Could not load request timeline. \(error.localizedDescription)"
    }
}
