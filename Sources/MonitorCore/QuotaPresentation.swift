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
    public let accountScopeID: String?
    public let accountProfileID: String?
    public let accountProfileLabel: String?
    public let accountScopeState: UsageAccountScopeState
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
        id: String, accountScopeID: String? = nil, accountProfileID: String? = nil,
        accountProfileLabel: String? = nil, accountScopeState: UsageAccountScopeState = .unknown,
        scope: UsageLimitScope, scopeIdentifier: String?, limitID: String?,
        limitName: String?, planType: String?, slot: UsageLimitWindowSlot,
        windowKind: UsageLimitWindowKind, windowMinutes: Int64?, usedPercent: Double?,
        remainingPercent: Double?, resetsAt: Date?, observedAt: Date, freshness: QuotaFreshness,
        isResetDiscontinuity: Bool, resetDiscontinuity: QuotaResetDiscontinuity? = nil,
        isAmbiguous: Bool = false
    ) {
        self.id = id
        self.accountScopeID = accountScopeID
        self.accountProfileID = accountProfileID
        self.accountProfileLabel = accountProfileLabel
        self.accountScopeState = accountScopeState
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

/// Coverage for one resolved quota account scope, including snapshots that carry no windows.
public struct QuotaAccountCoverage: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let accountScopeID: String?
    public let accountProfileID: String?
    public let accountProfileLabel: String?
    public let accountScopeState: UsageAccountScopeState
    public let coverage: UsageLimitTelemetryCoverage

    public init(snapshots: [UsageLimitSnapshotObservation]) {
        let first = snapshots.first
        accountScopeID = first?.accountScopeID
        accountProfileID = first?.accountProfileID
        accountProfileLabel = first?.accountProfileLabel
        accountScopeState = first?.accountScopeState ?? .unknown
        id = "\(accountScopeID ?? "no-scope")|\(accountScopeState.rawValue)"
        coverage = UsageLimitTelemetryCoverage(snapshots: snapshots)
    }
}

public struct QuotaPresentationReport: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let query: UsageQuery
    public let generatedAt: Date
    public let freshnessThresholdSeconds: TimeInterval
    public let coverage: UsageLimitTelemetryCoverage
    public let accountCoverages: [QuotaAccountCoverage]
    public let windows: [QuotaWindowPresentation]

    public init(
        query: UsageQuery, generatedAt: Date, freshnessThresholdSeconds: TimeInterval,
        coverage: UsageLimitTelemetryCoverage, accountCoverages: [QuotaAccountCoverage] = [],
        windows: [QuotaWindowPresentation]
    ) {
        schemaVersion = 1
        self.query = query
        self.generatedAt = generatedAt
        self.freshnessThresholdSeconds = freshnessThresholdSeconds
        self.coverage = coverage
        self.accountCoverages = accountCoverages
        self.windows = windows
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, query, generatedAt, freshnessThresholdSeconds, coverage, accountCoverages, windows
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        query = try values.decode(UsageQuery.self, forKey: .query)
        generatedAt = try values.decode(Date.self, forKey: .generatedAt)
        freshnessThresholdSeconds = try values.decode(TimeInterval.self, forKey: .freshnessThresholdSeconds)
        coverage = try values.decode(UsageLimitTelemetryCoverage.self, forKey: .coverage)
        accountCoverages = try values.decodeIfPresent([QuotaAccountCoverage].self, forKey: .accountCoverages) ?? []
        windows = try values.decode([QuotaWindowPresentation].self, forKey: .windows)
    }
}
