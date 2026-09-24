import Foundation

public enum QuotaAnomalyOutcome: String, Codable, CaseIterable, Sendable {
    case stableUsage = "stable_usage"
    case sharpShift = "sharp_shift"
    case resetDiscontinuity = "reset_discontinuity"
    case unknown
    case notApplicable = "not_applicable"
}

public enum QuotaAnomalyReason: String, Codable, CaseIterable, Sendable {
    case noSnapshots = "no_snapshots"
    case unknownAccountScope = "unknown_account_scope"
    case incompleteCoverage = "incomplete_coverage"
    case unsupportedSnapshot = "unsupported_snapshot"
    case missingWindowIdentity = "missing_window_identity"
    case missingReset = "missing_reset"
    case staleObservation = "stale_observation"
    case ambiguousObservation = "ambiguous_observation"
    case insufficientHistory = "insufficient_history"
    case zeroMedianAbsoluteDeviation = "zero_mad"
}

public enum QuotaSessionAttribution: String, Codable, CaseIterable, Sendable {
    case notApplicable = "not_applicable"
}

/// Account-level quota evidence is kept separate from session anomaly findings.
/// `sourceContextSessionID` is never copied into a session attribution field.
public struct QuotaAnomalyAssessment: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let outcome: QuotaAnomalyOutcome
    public let reason: QuotaAnomalyReason?
    public let sessionAttribution: QuotaSessionAttribution
    public let accountScopeID: String?
    public let accountProfileID: String?
    public let accountProfileLabel: String?
    public let accountScopeState: UsageAccountScopeState
    public let scope: UsageLimitScope?
    public let scopeIdentifier: String?
    public let limitID: String?
    public let limitName: String?
    public let slot: UsageLimitWindowSlot?
    public let windowMinutes: Int64?
    public let resetsAt: Date?
    public let previousObservedAt: Date?
    public let currentObservedAt: Date?
    public let rateChangePercentagePointsPerHour: Double?
    public let baselineMedianPercentagePointsPerHour: Double?
    public let robustZScore: Double?
    public let evidence: DiagnosticEvidence

    public init(
        id: String, outcome: QuotaAnomalyOutcome, reason: QuotaAnomalyReason? = nil,
        sessionAttribution: QuotaSessionAttribution = .notApplicable,
        accountScopeID: String? = nil, accountProfileID: String? = nil, accountProfileLabel: String? = nil,
        accountScopeState: UsageAccountScopeState = .unknown, scope: UsageLimitScope? = nil,
        scopeIdentifier: String? = nil, limitID: String? = nil, limitName: String? = nil,
        slot: UsageLimitWindowSlot? = nil, windowMinutes: Int64? = nil, resetsAt: Date? = nil,
        previousObservedAt: Date? = nil, currentObservedAt: Date? = nil,
        rateChangePercentagePointsPerHour: Double? = nil,
        baselineMedianPercentagePointsPerHour: Double? = nil, robustZScore: Double? = nil,
        evidence: DiagnosticEvidence
    ) {
        self.id = id
        self.outcome = outcome
        self.reason = reason
        self.sessionAttribution = sessionAttribution
        self.accountScopeID = accountScopeID
        self.accountProfileID = accountProfileID
        self.accountProfileLabel = accountProfileLabel
        self.accountScopeState = accountScopeState
        self.scope = scope
        self.scopeIdentifier = scopeIdentifier
        self.limitID = limitID
        self.limitName = limitName
        self.slot = slot
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
        self.previousObservedAt = previousObservedAt
        self.currentObservedAt = currentObservedAt
        self.rateChangePercentagePointsPerHour = rateChangePercentagePointsPerHour
        self.baselineMedianPercentagePointsPerHour = baselineMedianPercentagePointsPerHour
        self.robustZScore = robustZScore
        self.evidence = evidence
    }
}
