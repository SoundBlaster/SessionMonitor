import Foundation
import MonitorCore

// swiftlint:disable function_parameter_count line_length

extension UsageStore {
    static func sourceFinding(
        id: String, severity: DiagnosticSeverity, title: String, explanation: String,
        counts: [(String, Int64)], action: String
    ) -> DiagnosticFinding {
        let detail = counts.map { "\($0.0)=\($0.1)" }.joined(separator: ", ")
        return DiagnosticFinding(
            id: id, severity: severity, title: title, explanation: explanation,
            evidence: DiagnosticEvidence(
                observed: [DiagnosticEvidenceItem(source: "source_diagnostics", detail: detail)],
                unknown: [DiagnosticEvidenceItem(
                    source: "source_diagnostics", detail: "Source diagnostics are not session-scoped; affected sessions are unknown."
                )], limitations: ["This finding is database-wide for the selected imported store."]
            ), confidence: .high, affectedSessions: [], suggestedNextAction: action
        )
    }

    static func diagnosticCounts(_ diagnostics: [String: Int64], keys: [String]) -> [(String, Int64)] {
        keys.compactMap { key in diagnostics[key].map { (key, $0) } }.filter { $0.1 > 0 }
    }

    static func inputTokens(_ point: RequestTimelinePoint) -> Int64? {
        guard let cached = point.cachedInputTokens, let uncached = point.uncachedInputTokens else { return nil }
        return cached + uncached
    }

    static func cacheRatio(_ point: RequestTimelinePoint) -> Double? {
        guard let input = inputTokens(point), input > 0, let cached = point.cachedInputTokens else { return nil }
        return Double(cached) / Double(input)
    }

    static func median(_ values: [Int64]) -> Double? {
        guard !values.isEmpty else { return nil }
        if values.count % 2 == 1 { return Double(values[values.count / 2]) }
        let upper = values.count / 2
        return Double(values[upper - 1] + values[upper]) / 2
    }

    static func percentage(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
    // swiftlint:disable:next function_body_length
    static func inspectionEvidence(
        sessionID: String, summary: SessionSummary, timeline: RequestTimeline,
        provenance: SessionProvenance?, diagnostics: [String: Int64]
    ) -> DiagnosticEvidence {
        let requestPoints = timeline.points.filter { $0.kind == .usageRequest }
        let eventPoints = timeline.points.filter { $0.kind != .usageRequest }
        var observed: [DiagnosticEvidenceItem] = []
        if !requestPoints.isEmpty {
            observed.append(DiagnosticEvidenceItem(
                source: "confirmed", detail: "Canonical totals contain \(summary.totals.requests) confirmed requests.",
                sessionIDs: [sessionID], responseIDs: requestPoints.compactMap(\.responseID).sorted()
            ))
        }
        if !eventPoints.isEmpty {
            observed.append(DiagnosticEvidenceItem(
                source: "source_timeline_events", detail: "Explicit timeline events were persisted.",
                sessionIDs: [sessionID], sourceLines: eventPoints.compactMap(\.sourceLine).sorted()
            ))
        }
        if provenance != nil {
            observed.append(DiagnosticEvidenceItem(
                source: "source_provenance",
                detail: "Explicit session provenance metadata was persisted.", sessionIDs: [sessionID]
            ))
        }
        var unknown: [DiagnosticEvidenceItem] = []
        if summary.totals.unknownCacheRequests > 0 {
            unknown.append(DiagnosticEvidenceItem(
                source: "confirmed",
                detail: "\(summary.totals.unknownCacheRequests) request(s) have unknown cached input.",
                sessionIDs: [sessionID]
            ))
        }
        if provenance == nil {
            unknown.append(DiagnosticEvidenceItem(
                source: "source_provenance",
                detail: "Provenance is unavailable for this session.", sessionIDs: [sessionID]
            ))
        } else if provenance?.efforts.isEmpty == true || provenance?.clientVersion == nil {
            unknown.append(DiagnosticEvidenceItem(
                source: "source_provenance",
                detail: "Optional effort or client-version metadata is absent.", sessionIDs: [sessionID]
            ))
        }
        if timeline.points.isEmpty {
            unknown.append(DiagnosticEvidenceItem(
                source: "source_timeline_events",
                detail: "No explicit timeline evidence is available for the selected query.",
                sessionIDs: [sessionID]
            ))
        }
        var limitations = ["Timeline events are presentation evidence and never change canonical totals."]
        if summary.totals.unknownCacheRequests > 0 {
            limitations.append("Cache hit ratio is omitted because cache coverage is partial.")
        }
        if !diagnostics.isEmpty {
            limitations.append(
                "Source diagnostics are database-wide and are not attributed to this session without explicit evidence."
            )
        }
        return DiagnosticEvidence(observed: observed, unknown: unknown, limitations: limitations)
    }
}

enum ComparisonResult {
    case orderedAscending
    case orderedSame
    case orderedDescending
}

struct CacheChange {
    let before: RequestTimelinePoint
    let after: RequestTimelinePoint
    let change: Double
}

// swiftlint:enable function_parameter_count line_length
