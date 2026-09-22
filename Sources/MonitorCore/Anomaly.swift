import Foundation

public enum AnomalyKind: String, Codable, CaseIterable, Sendable {
    case repetitivePolling = "repetitive_polling"
    case startupOverhead = "excessive_startup_overhead"
    case cacheDrop = "unusual_cache_changes"
    case cacheRecovery = "cache_recovery"
    case highAbsoluteUsage = "high_absolute_usage"
    case dominantSession = "dominant_session_usage"
    case uncachedBurst = "uncached_burst"
}

public enum AnomalyCoverage: Codable, Equatable, Sendable {
    case observed
    case partial(reason: String)
    case unknown(reason: String)
}

/// A policy result retains machine-readable classification alongside explanatory evidence.
public struct AnomalyFinding: Codable, Equatable, Sendable, Identifiable {
    public let kind: AnomalyKind
    public let title: String
    public let reason: String
    public let severity: DiagnosticSeverity
    public let evidence: DiagnosticEvidence
    public let confidence: DiagnosticConfidence
    public let coverage: AnomalyCoverage
    public let affectedSessions: [String]
    public let suggestedNextAction: String

    public var id: String {
        let sessions = affectedSessions.sorted().joined(separator: ",")
        let responseIDs = evidence.observed.flatMap(\.responseIDs).sorted().joined(separator: ",")
        let sourceLines = evidence.observed.flatMap(\.sourceLines).sorted().map(String.init).joined(separator: ",")
        return [kind.rawValue, sessions, responseIDs, sourceLines].joined(separator: "|")
    }

    public init(
        kind: AnomalyKind, title: String, reason: String, severity: DiagnosticSeverity,
        evidence: DiagnosticEvidence, confidence: DiagnosticConfidence, coverage: AnomalyCoverage,
        affectedSessions: [String], suggestedNextAction: String
    ) {
        self.kind = kind
        self.title = title
        self.reason = reason
        self.severity = severity
        self.evidence = evidence
        self.confidence = confidence
        self.coverage = coverage
        self.affectedSessions = affectedSessions
        self.suggestedNextAction = suggestedNextAction
    }
}
