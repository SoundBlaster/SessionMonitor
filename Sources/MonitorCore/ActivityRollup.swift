import Foundation

public enum ActivityCoverageState: String, Codable, Sendable {
    case observed
    case unknown
}

public struct ActivityCoverage: Codable, Equatable, Sendable {
    public let state: ActivityCoverageState
    public let unknownReason: String?
    public let observedToolEvents: Int64
    public let unknownClassEvents: Int64

    public init(state: ActivityCoverageState, unknownReason: String?, observedToolEvents: Int64,
                unknownClassEvents: Int64) {
        self.state = state
        self.unknownReason = unknownReason
        self.observedToolEvents = observedToolEvents
        self.unknownClassEvents = unknownClassEvents
    }
}

public struct ActivityUsageRollup: Codable, Equatable, Sendable {
    public let sessionID: String
    public let model: String
    public let responses: Int64
    public let inputTokens: Int64
    public let cachedInputTokens: Int64
    public let uncachedInputTokens: Int64?
    public let outputTokens: Int64
    public let unknownCacheResponses: Int64
    public let cacheHitRatio: Double?

    public init(sessionID: String, model: String, totals: UsageTotals) {
        self.sessionID = sessionID
        self.model = model
        responses = totals.requests
        inputTokens = totals.inputTokens
        cachedInputTokens = totals.cachedInputTokens
        uncachedInputTokens = totals.unknownCacheRequests == 0
            ? totals.inputTokens - totals.cachedInputTokens
            : nil
        outputTokens = totals.outputTokens
        unknownCacheResponses = totals.unknownCacheRequests
        cacheHitRatio = totals.cacheHitRatio
    }
}

public struct ActivityModelRollup: Codable, Equatable, Sendable {
    public let model: String
    public let responses: Int64
    public let inputTokens: Int64
    public let cachedInputTokens: Int64
    public let uncachedInputTokens: Int64?
    public let outputTokens: Int64
    public let unknownCacheResponses: Int64
    public let cacheHitRatio: Double?

    public init(model: String, totals: UsageTotals) {
        self.model = model
        responses = totals.requests
        inputTokens = totals.inputTokens
        cachedInputTokens = totals.cachedInputTokens
        uncachedInputTokens = totals.unknownCacheRequests == 0
            ? totals.inputTokens - totals.cachedInputTokens
            : nil
        outputTokens = totals.outputTokens
        unknownCacheResponses = totals.unknownCacheRequests
        cacheHitRatio = totals.cacheHitRatio
    }
}

/// Counts source events. Calls and result/output events remain separate through their evidence type.
public struct ActivityToolEventRollup: Codable, Equatable, Sendable, Identifiable {
    public let sessionID: String
    public let model: String?
    public let classification: ActivityToolClass
    public let toolName: String?
    public let evidence: String
    public let count: Int64
    public let sourceLines: [Int]

    public var id: String {
        [sessionID, model ?? "unknown", classification.rawValue, toolName ?? "unknown", evidence]
            .joined(separator: "|")
    }

    public init(sessionID: String, model: String?, classification: ActivityToolClass, toolName: String?,
                evidence: String, count: Int64, sourceLines: [Int]) {
        self.sessionID = sessionID
        self.model = model
        self.classification = classification
        self.toolName = toolName
        self.evidence = evidence
        self.count = count
        self.sourceLines = sourceLines.sorted()
    }
}

/// Auxiliary activity evidence. Usage totals remain the canonical, deduplicated accounting view.
public struct ActivityRollupReport: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let query: UsageQuery
    public let sessionID: String?
    public let rootSessionID: String?
    public let totals: UsageTotals
    public let usageByThreadAndModel: [ActivityUsageRollup]
    public let usageByModel: [ActivityModelRollup]
    public let toolEvents: [ActivityToolEventRollup]
    public let coverage: ActivityCoverage

    public init(query: UsageQuery, sessionID: String?, rootSessionID: String?, totals: UsageTotals,
                usageByThreadAndModel: [ActivityUsageRollup], usageByModel: [ActivityModelRollup],
                toolEvents: [ActivityToolEventRollup],
                coverage: ActivityCoverage) {
        schemaVersion = 1
        self.query = query
        self.sessionID = sessionID
        self.rootSessionID = rootSessionID
        self.totals = totals
        self.usageByThreadAndModel = usageByThreadAndModel
        self.usageByModel = usageByModel
        self.toolEvents = toolEvents
        self.coverage = coverage
    }
}
