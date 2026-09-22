import Foundation
import GRDB
import MonitorCore
import MonitorPolicies

public enum DiagnosticsQueryError: Error {
    case snapshotUnavailable
}

extension UsageStore {
    public func listSessions(
        query: UsageQuery, sort: SessionListSort = .input, descending: Bool = true,
        model: String? = nil, idPrefix: String? = nil, relationship: SessionTreeState? = nil
    ) throws -> SessionListReport {
        let snapshot = try diagnosticSnapshot(query: query)
        let states = Self.treeStates(sessions: snapshot.report.sessions, provenance: snapshot.provenance)
        let items = snapshot.report.sessions.map { session in
            let provenance = snapshot.provenance[session.id]
            let totals = session.totals
            let status: QueryCoverage.Cache
            if totals.requests == 0 {
                status = .empty
            } else {
                status = totals.unknownCacheRequests == 0 ? .complete : .partial
            }
            return SessionListItem(
                id: session.id, displayName: provenance?.displayName, model: session.model, totals: totals,
                cacheCoverage: status, cacheHitRatio: totals.cacheHitRatio,
                provenanceState: provenance == nil ? .missing : .present,
                relationshipState: states[session.id] ?? .unknown
            )
        }.filter { item in
            (model == nil || item.model == model)
                && (idPrefix == nil || item.id.hasPrefix(idPrefix ?? ""))
                && (relationship == nil || item.relationshipState == relationship)
        }.sorted { lhs, rhs in
            let result: ComparisonResult
            switch sort {
            case .input: result = compare(lhs.totals.inputTokens, rhs.totals.inputTokens)
            case .requests: result = compare(lhs.totals.requests, rhs.totals.requests)
            case .cached: result = compare(lhs.totals.cachedInputTokens, rhs.totals.cachedInputTokens)
            case .output: result = compare(lhs.totals.outputTokens, rhs.totals.outputTokens)
            case .id:
                result = lhs.id == rhs.id
                    ? .orderedSame
                    : (lhs.id < rhs.id ? .orderedAscending : .orderedDescending)
            }
            if result != .orderedSame { return descending ? result == .orderedDescending : result == .orderedAscending }
            return descending ? lhs.id > rhs.id : lhs.id < rhs.id
        }
        return SessionListReport(query: query, sort: sort, descending: descending, sessions: items)
    }

    public func inspect(sessionID: String, query: UsageQuery) throws -> SessionInspection? {
        let snapshot = try diagnosticSnapshot(query: query)
        guard let summary = snapshot.report.sessions.first(where: { $0.id == sessionID }) else { return nil }
        let timeline = try self.timeline(sessionID: sessionID, query: query)
        let provenance = snapshot.provenance[sessionID]
        let states = Self.treeStates(sessions: snapshot.report.sessions, provenance: snapshot.provenance)
        let totals = summary.totals
        let cacheStatus: QueryCoverage.Cache
        if totals.requests == 0 {
            cacheStatus = .empty
        } else {
            cacheStatus = totals.unknownCacheRequests == 0 ? .complete : .partial
        }
        let cache = SessionCacheCoverage(
            status: cacheStatus, knownRequests: totals.requests - totals.unknownCacheRequests,
            unknownRequests: totals.unknownCacheRequests, hitRatio: totals.cacheHitRatio
        )
        let counts = Dictionary(grouping: timeline.points, by: { $0.kind.rawValue })
            .mapValues { Int64($0.count) }
        let timestamps = timeline.points.map(\.timestamp)
        let first = timestamps.min()
        let last = timestamps.max()
        let duration = first.flatMap { start in last.map { end in max(0, end.timeIntervalSince(start)) } }
        let relationship = SessionRelationshipInfo(
            state: states[sessionID] ?? .unknown, kind: provenance?.relationship?.kind,
            parentSessionID: provenance?.relationship?.parentSessionID, rootSessionID: provenance?.rootSessionID
        )
        return SessionInspection(
            query: query, sessionID: sessionID, model: summary.model,
            effort: provenance?.efforts ?? [], clientVersion: provenance?.clientVersion,
            totals: totals, cache: cache,
            timeline: SessionTimelineSummary(
                usageRequests: Int64(timeline.points.filter { $0.kind == .usageRequest }.count),
                eventCounts: counts, firstTimestamp: first, lastTimestamp: last, durationSeconds: duration
            ), relationship: relationship,
            evidence: Self.inspectionEvidence(
                sessionID: sessionID, summary: summary, timeline: timeline, provenance: provenance,
                diagnostics: snapshot.report.diagnostics
            )
        )
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    public func doctor(
        query: UsageQuery, configuration: AnomalyPolicyConfiguration = .init()
    ) throws -> DiagnosticReport {
        let snapshot = try diagnosticSnapshot(query: query)
        let states = Self.treeStates(sessions: snapshot.report.sessions, provenance: snapshot.provenance)
        let timelines = Dictionary(uniqueKeysWithValues: try snapshot.report.sessions.map { session in
            (session.id, try self.timeline(sessionID: session.id, query: query))
        })
        var findings: [DiagnosticFinding] = []
        let policyEngine = AnomalyPolicyEngine(configuration: configuration)
        let cohort = snapshot.report.sessions

        for session in snapshot.report.sessions {
            guard let timeline = timelines[session.id] else { continue }
            findings.append(contentsOf: policyEngine.evaluate(
                AnomalyPolicyContext(session: session, timeline: timeline, cohort: cohort)
            ).map { $0.asDiagnosticFinding() })
        }

        let missingProvenance = snapshot.report.sessions.filter { snapshot.provenance[$0.id] == nil }
        if !missingProvenance.isEmpty {
            let ids = missingProvenance.map(\.id).sorted()
            findings.append(DiagnosticFinding(
                id: "missing_provenance", severity: .warning, title: "Missing provenance",
                explanation: "Canonical usage exists for sessions without persisted provenance metadata.",
                evidence: DiagnosticEvidence(
                    observed: [DiagnosticEvidenceItem(
                        source: "confirmed", detail: "Sessions have canonical confirmed usage records.", sessionIDs: ids
                    )],
                    unknown: [DiagnosticEvidenceItem(
                        source: "source_provenance",
                        detail: "No provenance row was available for these sessions.", sessionIDs: ids
                    )],
                    limitations: ["No parent, client, effort or display-name inference was made."]
                ), confidence: .high, affectedSessions: ids,
                suggestedNextAction: "Re-import the source so explicit session metadata can be persisted."
            ))
        }

        for state in [SessionTreeState.orphan, .conflict, .cycle] {
            let ids = snapshot.report.sessions.filter { states[$0.id] == state }.map(\.id).sorted()
            guard !ids.isEmpty else { continue }
            let id: String
            let title: String
            let explanation: String
            let action: String
            switch state {
            case .orphan:
                id = "relationship_orphan"
                title = "Orphan relationship"
                explanation = "A session explicitly names a parent that is not present in the selected session set."
                action = "Verify that the parent source was imported and that its metadata is complete."
            case .conflict:
                id = "relationship_conflict"
                title = "Conflicting relationship"
                explanation = "Explicit parent and root relationship evidence disagree."
                action = "Inspect the source metadata for the affected sessions and resolve the "
                    + "conflicting relationship evidence."
            case .cycle:
                id = "relationship_cycle"
                title = "Cyclic relationship"
                explanation = "Explicit parent relationships form a cycle."
                action = "Repair the source relationship metadata before relying on the session tree."
            default:
                continue
            }
            findings.append(DiagnosticFinding(
                id: id, severity: .warning, title: title, explanation: explanation,
                evidence: DiagnosticEvidence(
                    observed: [DiagnosticEvidenceItem(
                        source: "source_provenance",
                        detail: "Explicit parent/root metadata is present.", sessionIDs: ids
                    )],
                    inference: [DiagnosticEvidenceItem(
                        source: "session_tree",
                        detail: "SessionTreeBuilder classified the relationship as \(state.rawValue).",
                        sessionIDs: ids
                    )],
                    unknown: [DiagnosticEvidenceItem(
                        source: "source_provenance",
                        detail: "The source does not explain whether the relationship is intentional.",
                        sessionIDs: ids
                    )]
                ), confidence: .high, affectedSessions: ids, suggestedNextAction: action
            ))
        }

        let malformed = Self.diagnosticCounts(snapshot.report.diagnostics, keys: [
            "malformedRecords", "invalidUsageOrIdentity", "oversizedLines"
        ])
        if !malformed.isEmpty {
            findings.append(Self.sourceFinding(
                id: "malformed_source_evidence", severity: .error, title: "Malformed source evidence",
                explanation: "Imported source diagnostics report malformed, invalid or oversized records.",
                counts: malformed,
                action: "Inspect the source records and re-import after correcting or isolating malformed input."
            ))
        }
        let incomplete = Self.diagnosticCounts(snapshot.report.diagnostics, keys: [
            "partialTails", "unownedOrUnprovenRecords"
        ])
        if !incomplete.isEmpty {
            findings.append(Self.sourceFinding(
                id: "incomplete_source_evidence", severity: .warning, title: "Incomplete source evidence",
                explanation: "Imported source diagnostics indicate a partial tail or records without proven ownership.",
                counts: incomplete,
                action: "Complete the source write or verify ownership, then re-import the affected source."
            ))
        }

        return DiagnosticReport(query: query, findings: findings.sorted { $0.id < $1.id })
    }

    private func diagnosticSnapshot(query: UsageQuery) throws -> UsageSnapshot {
        guard let snapshot = try snapshot(query: query) else { throw DiagnosticsQueryError.snapshotUnavailable }
        return snapshot
    }

    private func compare(_ lhs: Int64, _ rhs: Int64) -> ComparisonResult {
        if lhs == rhs { return .orderedSame }
        return lhs < rhs ? .orderedAscending : .orderedDescending
    }

    private static func treeStates(
        sessions: [SessionSummary], provenance: [String: SessionProvenance]
    ) -> [String: SessionTreeState] {
        var result: [String: SessionTreeState] = [:]
        func visit(_ node: SessionTreeNode) {
            result[node.id] = node.state
            node.children.forEach(visit)
        }
        SessionTreeBuilder.build(sessions: sessions, provenance: provenance).forEach(visit)
        return result
    }
}
