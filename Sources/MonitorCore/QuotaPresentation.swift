import Foundation

public enum QuotaFreshnessState: String, Codable, CaseIterable, Sendable {
    case current
    case stale
    case future
    case unknown
}

public struct QuotaFreshness: Codable, Equatable, Sendable {
    public let state: QuotaFreshnessState
    public let ageSeconds: TimeInterval?

    public init(state: QuotaFreshnessState, ageSeconds: TimeInterval?) {
        self.state = state
        self.ageSeconds = ageSeconds
    }
}

public struct QuotaResetDiscontinuity: Codable, Equatable, Sendable {
    public let previousObservedAt: Date
    public let previousUsedPercent: Double?
    public let previousRemainingPercent: Double?
    public let previousResetsAt: Date
    public let currentObservedAt: Date
    public let currentUsedPercent: Double?
    public let currentRemainingPercent: Double?
    public let currentResetsAt: Date

    public init(
        previousObservedAt: Date, previousUsedPercent: Double?, previousRemainingPercent: Double?,
        previousResetsAt: Date, currentObservedAt: Date, currentUsedPercent: Double?,
        currentRemainingPercent: Double?, currentResetsAt: Date
    ) {
        self.previousObservedAt = previousObservedAt
        self.previousUsedPercent = previousUsedPercent
        self.previousRemainingPercent = previousRemainingPercent
        self.previousResetsAt = previousResetsAt
        self.currentObservedAt = currentObservedAt
        self.currentUsedPercent = currentUsedPercent
        self.currentRemainingPercent = currentRemainingPercent
        self.currentResetsAt = currentResetsAt
    }
}

public struct QuotaWindowPresentation: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let scope: UsageLimitScope
    public let scopeIdentifier: String?
    public let limitID: String?
    public let limitName: String?
    public let planType: String?
    public let slot: UsageLimitWindowSlot
    public let windowKind: UsageLimitWindowKind
    public let windowMinutes: Int64?
    public let usedPercent: Double?
    public let remainingPercent: Double?
    public let resetsAt: Date?
    public let observedAt: Date
    public let freshness: QuotaFreshness
    public let isResetDiscontinuity: Bool
    public let resetDiscontinuity: QuotaResetDiscontinuity?
    public let isAmbiguous: Bool

    public init(
        id: String, scope: UsageLimitScope, scopeIdentifier: String?, limitID: String?,
        limitName: String?, planType: String?, slot: UsageLimitWindowSlot,
        windowKind: UsageLimitWindowKind, windowMinutes: Int64?, usedPercent: Double?,
        remainingPercent: Double?, resetsAt: Date?, observedAt: Date, freshness: QuotaFreshness,
        isResetDiscontinuity: Bool, resetDiscontinuity: QuotaResetDiscontinuity? = nil,
        isAmbiguous: Bool = false
    ) {
        self.id = id
        self.scope = scope
        self.scopeIdentifier = scopeIdentifier
        self.limitID = limitID
        self.limitName = limitName
        self.planType = planType
        self.slot = slot
        self.windowKind = windowKind
        self.windowMinutes = windowMinutes
        self.usedPercent = usedPercent
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
        self.observedAt = observedAt
        self.freshness = freshness
        self.isResetDiscontinuity = isResetDiscontinuity
        self.resetDiscontinuity = resetDiscontinuity
        self.isAmbiguous = isAmbiguous
    }
}

public struct QuotaPresentationReport: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let query: UsageQuery
    public let generatedAt: Date
    public let freshnessThresholdSeconds: TimeInterval
    public let coverage: UsageLimitTelemetryCoverage
    public let windows: [QuotaWindowPresentation]

    public init(
        query: UsageQuery, generatedAt: Date, freshnessThresholdSeconds: TimeInterval,
        coverage: UsageLimitTelemetryCoverage, windows: [QuotaWindowPresentation]
    ) {
        schemaVersion = 1
        self.query = query
        self.generatedAt = generatedAt
        self.freshnessThresholdSeconds = freshnessThresholdSeconds
        self.coverage = coverage
        self.windows = windows
    }
}
