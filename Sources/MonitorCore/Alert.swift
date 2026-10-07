import Foundation

/// Which evaluated domain produced an alert. Signal adapters are added separately from the pipeline.
public enum AlertSource: String, Codable, CaseIterable, Sendable {
    case anomaly
    case quota
    case importDiagnostics = "import_diagnostics"
    case watch
    case cacheThreshold = "cache_threshold"
    case liveRule = "live_rule"
}

/// One evaluated unit, for example `anomaly:session:<id>`. Only active alerts inside an evaluated
/// scope can be resolved by that evaluation; alerts from other scopes stay untouched.
public struct AlertScope: Codable, Hashable, Comparable, Sendable {
    public let id: String

    public init(_ id: String) { self.id = id }

    public static func < (lhs: AlertScope, rhs: AlertScope) -> Bool { lhs.id < rhs.id }
}

/// A signal that currently holds. `key` must be stable for the same underlying condition.
public struct AlertCandidate: Codable, Equatable, Sendable {
    public let key: String
    public let scope: AlertScope
    public let source: AlertSource
    public let kind: String
    public let severity: DiagnosticSeverity
    public let title: String
    public let message: String
    public let sessionIDs: [String]
    public let accountScopeID: String?
    public let coverage: AnomalyCoverage
    public let evidence: DiagnosticEvidence

    public init(
        key: String, scope: AlertScope, source: AlertSource, kind: String, severity: DiagnosticSeverity,
        title: String, message: String, sessionIDs: [String] = [], accountScopeID: String? = nil,
        coverage: AnomalyCoverage = .observed, evidence: DiagnosticEvidence = DiagnosticEvidence()
    ) {
        self.key = key
        self.scope = scope
        self.source = source
        self.kind = kind
        self.severity = severity
        self.title = title
        self.message = message
        self.sessionIDs = sessionIDs.sorted()
        self.accountScopeID = accountScopeID
        self.coverage = coverage
        self.evidence = evidence
    }
}

/// The complete set of signals found in the evaluated scopes at one observation time.
public struct AlertEvaluation: Sendable {
    public let scopes: Set<AlertScope>
    public let candidates: [AlertCandidate]
    public let observedAt: Date

    /// Candidate scopes are always treated as evaluated, even when the caller omits them.
    public init(scopes: Set<AlertScope>, candidates: [AlertCandidate], observedAt: Date) {
        self.scopes = scopes.union(candidates.map(\.scope))
        self.candidates = candidates
        self.observedAt = observedAt
    }
}

public enum AlertStatus: String, Codable, CaseIterable, Sendable {
    case active
    case resolved
}

/// Persistent alert state. `firstSeenAt` survives re-raising; `raisedAt` is the current occurrence.
public struct AlertRecord: Codable, Equatable, Identifiable, Sendable {
    public let candidate: AlertCandidate
    public let status: AlertStatus
    public let firstSeenAt: Date
    public let raisedAt: Date
    public let lastSeenAt: Date
    public let resolvedAt: Date?
    public let lastNotifiedAt: Date?
    public let occurrences: Int

    public var id: String { candidate.key }

    public init(
        candidate: AlertCandidate, status: AlertStatus, firstSeenAt: Date, raisedAt: Date, lastSeenAt: Date,
        resolvedAt: Date? = nil, lastNotifiedAt: Date? = nil, occurrences: Int = 1
    ) {
        self.candidate = candidate
        self.status = status
        self.firstSeenAt = firstSeenAt
        self.raisedAt = raisedAt
        self.lastSeenAt = lastSeenAt
        self.resolvedAt = resolvedAt
        self.lastNotifiedAt = lastNotifiedAt
        self.occurrences = occurrences
    }
}

public enum AlertTransition: String, Codable, CaseIterable, Sendable {
    case raised
    case escalated
    case updated
    case resolved
}

/// Why a transition was recorded without asking sinks to interrupt the user.
public enum AlertSuppression: String, Codable, CaseIterable, Sendable {
    case belowMinimumSeverity = "below_minimum_severity"
    case muted
    case uncertainCoverage = "uncertain_coverage"
    case cooldown
    case rateLimited = "rate_limited"
    case resolutionNotRequested = "resolution_not_requested"
    case notEscalated = "not_escalated"
}

/// One state change. Every sink receives every event; `notify` marks interrupting delivery.
public struct AlertEvent: Codable, Equatable, Sendable {
    public let transition: AlertTransition
    public let record: AlertRecord
    public let notify: Bool
    public let suppression: AlertSuppression?

    public init(transition: AlertTransition, record: AlertRecord, notify: Bool, suppression: AlertSuppression?) {
        self.transition = transition
        self.record = record
        self.notify = notify
        self.suppression = notify ? nil : suppression
    }
}
