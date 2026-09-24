import Foundation

public enum DiagnosticSeverity: String, Codable, CaseIterable, Sendable {
    case info
    case warning
    case error
}

public enum DiagnosticConfidence: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
}

/// Evidence is deliberately separated into observed facts, bounded inference and unknowns.
/// Sources name persisted store contracts, never prompt text or guessed file names.
public struct DiagnosticEvidenceItem: Codable, Equatable, Sendable {
    public let source: String
    public let detail: String
    public let sessionIDs: [String]
    public let responseIDs: [String]
    public let sourceLines: [Int]

    public init(
        source: String, detail: String, sessionIDs: [String] = [], responseIDs: [String] = [],
        sourceLines: [Int] = []
    ) {
        self.source = source
        self.detail = detail
        self.sessionIDs = sessionIDs
        self.responseIDs = responseIDs
        self.sourceLines = sourceLines
    }
}

public struct DiagnosticEvidence: Codable, Equatable, Sendable {
    public let observed: [DiagnosticEvidenceItem]
    public let inference: [DiagnosticEvidenceItem]
    public let unknown: [DiagnosticEvidenceItem]
    public let limitations: [String]

    public init(
        observed: [DiagnosticEvidenceItem] = [], inference: [DiagnosticEvidenceItem] = [],
        unknown: [DiagnosticEvidenceItem] = [], limitations: [String] = []
    ) {
        self.observed = observed
        self.inference = inference
        self.unknown = unknown
        self.limitations = limitations
    }
}

public struct DiagnosticFinding: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let severity: DiagnosticSeverity
    public let title: String
    public let explanation: String
    public let evidence: DiagnosticEvidence
    public let confidence: DiagnosticConfidence
    public let coverage: AnomalyCoverage?
    public let affectedSessions: [String]
    public let suggestedNextAction: String

    public init(
        id: String, severity: DiagnosticSeverity, title: String, explanation: String,
        evidence: DiagnosticEvidence, confidence: DiagnosticConfidence,
        affectedSessions: [String], suggestedNextAction: String, coverage: AnomalyCoverage? = nil
    ) {
        self.id = id
        self.severity = severity
        self.title = title
        self.explanation = explanation
        self.evidence = evidence
        self.confidence = confidence
        self.coverage = coverage
        self.affectedSessions = affectedSessions
        self.suggestedNextAction = suggestedNextAction
    }
}

public enum SessionListSort: String, Codable, CaseIterable, Sendable {
    case input
    case requests
    case cached
    case output
    case id
}

public enum SessionProvenanceState: String, Codable, Sendable {
    case present
    case missing
}

public struct SessionListItem: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String?
    public let model: String
    public let totals: UsageTotals
    public let cacheCoverage: QueryCoverage.Cache
    public let cacheHitRatio: Double?
    public let provenanceState: SessionProvenanceState
    public let relationshipState: SessionTreeState

    public init(
        id: String, displayName: String? = nil, model: String, totals: UsageTotals,
        cacheCoverage: QueryCoverage.Cache, cacheHitRatio: Double?,
        provenanceState: SessionProvenanceState, relationshipState: SessionTreeState
    ) {
        self.id = id
        self.displayName = displayName
        self.model = model
        self.totals = totals
        self.cacheCoverage = cacheCoverage
        self.cacheHitRatio = cacheHitRatio
        self.provenanceState = provenanceState
        self.relationshipState = relationshipState
    }
}

public struct SessionListReport: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let query: UsageQuery
    public let sort: SessionListSort
    public let descending: Bool
    public let sessions: [SessionListItem]

    public init(query: UsageQuery, sort: SessionListSort, descending: Bool, sessions: [SessionListItem]) {
        schemaVersion = 1
        self.query = query
        self.sort = sort
        self.descending = descending
        self.sessions = sessions
    }
}

public struct SessionCacheCoverage: Codable, Equatable, Sendable {
    public let status: QueryCoverage.Cache
    public let knownRequests: Int64
    public let unknownRequests: Int64
    public let hitRatio: Double?

    public init(status: QueryCoverage.Cache, knownRequests: Int64, unknownRequests: Int64, hitRatio: Double?) {
        self.status = status
        self.knownRequests = knownRequests
        self.unknownRequests = unknownRequests
        self.hitRatio = hitRatio
    }
}

public struct SessionTimelineSummary: Codable, Equatable, Sendable {
    public let usageRequests: Int64
    public let eventCounts: [String: Int64]
    public let firstTimestamp: Date?
    public let lastTimestamp: Date?
    public let durationSeconds: Double?

    public init(
        usageRequests: Int64, eventCounts: [String: Int64], firstTimestamp: Date?,
        lastTimestamp: Date?, durationSeconds: Double?
    ) {
        self.usageRequests = usageRequests
        self.eventCounts = eventCounts
        self.firstTimestamp = firstTimestamp
        self.lastTimestamp = lastTimestamp
        self.durationSeconds = durationSeconds
    }
}

public struct SessionRelationshipInfo: Codable, Equatable, Sendable {
    public let state: SessionTreeState
    public let kind: SessionRelationshipKind?
    public let parentSessionID: String?
    public let rootSessionID: String?

    public init(
        state: SessionTreeState, kind: SessionRelationshipKind? = nil,
        parentSessionID: String? = nil, rootSessionID: String? = nil
    ) {
        self.state = state
        self.kind = kind
        self.parentSessionID = parentSessionID
        self.rootSessionID = rootSessionID
    }
}

public struct SessionInspection: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let query: UsageQuery
    public let sessionID: String
    public let model: String
    public let effort: [String]
    public let clientVersion: String?
    public let totals: UsageTotals
    public let cache: SessionCacheCoverage
    public let timeline: SessionTimelineSummary
    public let relationship: SessionRelationshipInfo
    public let evidence: DiagnosticEvidence

    public init(
        query: UsageQuery, sessionID: String, model: String, effort: [String], clientVersion: String?,
        totals: UsageTotals, cache: SessionCacheCoverage, timeline: SessionTimelineSummary,
        relationship: SessionRelationshipInfo, evidence: DiagnosticEvidence
    ) {
        schemaVersion = 1
        self.query = query
        self.sessionID = sessionID
        self.model = model
        self.effort = effort
        self.clientVersion = clientVersion
        self.totals = totals
        self.cache = cache
        self.timeline = timeline
        self.relationship = relationship
        self.evidence = evidence
    }
}

public struct DiagnosticReport: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let query: UsageQuery
    public let findings: [DiagnosticFinding]
    public let quotaAssessments: [QuotaAnomalyAssessment]

    public init(
        query: UsageQuery, findings: [DiagnosticFinding], quotaAssessments: [QuotaAnomalyAssessment] = []
    ) {
        schemaVersion = 1
        self.query = query
        self.findings = findings
        self.quotaAssessments = quotaAssessments
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, query, findings, quotaAssessments
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        query = try values.decode(UsageQuery.self, forKey: .query)
        findings = try values.decode([DiagnosticFinding].self, forKey: .findings)
        quotaAssessments = try values.decodeIfPresent([QuotaAnomalyAssessment].self, forKey: .quotaAssessments) ?? []
    }
}
