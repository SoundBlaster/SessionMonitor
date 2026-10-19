import MonitorCore
import SwiftUI

/// Cached UI projection, built with the policy report rather than on hover.
struct ContextInsightPresentation: Sendable {
    struct Marker: Identifiable, Equatable, Sendable {
        let index: Int
        let requestID: String
        let kind: ContextInsightKind
        let titles: String
        var id: String { requestID }
    }

    struct ZoneRow: Identifiable, Equatable, Sendable {
        let zone: ContextFillZone
        let phases: Int
        let requests: Int
        let input: Int64?
        let output: Int64?
        var id: ContextFillZone { zone }
    }

    let report: ContextInsightReport
    let markers: [Marker]
    let zones: [ZoneRow]
    let cardsByRequest: [Int: [ContextInsightCardPresentation]]
    static let markerSpacing = 28.0

    init(report: ContextInsightReport) {
        self.report = report
        cardsByRequest = report.insightsByRequest.mapValues { insights in
            insights.compactMap { insight in
                let offset = insight.requestIndex - 1
                guard report.anatomy.steps.indices.contains(offset) else { return nil }
                return ContextInsightCardPresentation(insight: insight, step: report.anatomy.steps[offset],
                                                      previous: offset > 0 ? report.anatomy.steps[offset - 1] : nil)
            }
        }
        markers = report.insightsByRequest.keys.sorted().compactMap { index in
            guard let values = report.insightsByRequest[index],
                  let primary = values.min(by: { Self.priority($0.kind) < Self.priority($1.kind) }) else { return nil }
            return Marker(index: index, requestID: primary.requestID, kind: primary.kind,
                          titles: values.map(\.title).joined(separator: "; "))
        }
        let phases = Dictionary(grouping: report.phases, by: \.zone)
        zones = ContextFillZone.allCases.compactMap { zone in
            guard let values = phases[zone] else { return nil }
            return ZoneRow(zone: zone, phases: values.count, requests: values.reduce(0) { $0 + $1.requests },
                           input: Self.sum(values.map(\.inputTokens)), output: Self.sum(values.map(\.outputTokens)))
        }
    }

    /// One representative per absolute request bin. IDs/positions never become viewport-relative slots.
    func visibleMarkers(in domain: ClosedRange<Double>, width: Double) -> [Marker] {
        guard width.isFinite, width > 0 else { return [] }
        let capacity = max(1, Int(width / Self.markerSpacing))
        let binWidth = max(1, ((domain.upperBound - domain.lowerBound) / Double(capacity)).rounded(.up))
        var bins: [Int: Marker] = [:]
        for marker in markers where domain.contains(Double(marker.index)) {
            let bin = Int((Double(marker.index) / binWidth).rounded(.down))
            if let existing = bins[bin], Self.priority(existing.kind) <= Self.priority(marker.kind) { continue }
            bins[bin] = marker
        }
        return bins.values.sorted { $0.index < $1.index }
    }

    static func zoneTitle(_ zone: ContextFillZone) -> LocalizedStringKey {
        switch zone {
        case .low: "Low"
        case .moderate: "Moderate"
        case .high: "High"
        case .critical: "Critical"
        }
    }

    static func symbol(_ kind: ContextInsightKind) -> String {
        switch kind {
        case .contextGrowth: "arrow.up.right"
        case .contextDrop: "arrow.down.right"
        case .compaction: "arrow.down.right.and.arrow.up.left"
        case .coldStart: "snowflake"
        case .cacheDropAfterPause: "clock"
        case .criticalEntry: "exclamationmark.triangle"
        }
    }

    private static func priority(_ kind: ContextInsightKind) -> Int {
        switch kind {
        case .criticalEntry: 0
        case .compaction: 1
        case .cacheDropAfterPause: 2
        case .contextDrop: 3
        case .contextGrowth: 4
        case .coldStart: 5
        }
    }

    private static func sum(_ values: [Int64?]) -> Int64? {
        values.reduce(Optional(Int64(0))) { total, value in
            guard let total, let value else { return nil }
            let (sum, overflow) = total.addingReportingOverflow(value)
            return overflow ? nil : sum
        }
    }
}
