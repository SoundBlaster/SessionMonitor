import Foundation

public struct UsageTotals: Codable, Equatable, Sendable {
    public var requests: Int64 = 0
    public var inputTokens: Int64 = 0
    public var cachedInputTokens: Int64 = 0
    public var outputTokens: Int64 = 0
    public var unknownCacheRequests: Int64 = 0
    public var cacheWriteInputTokens: Int64?
    public var reasoningOutputTokens: Int64?
    public var totalTokens: Int64?

    public var cacheHitRatio: Double? {
        guard requests > 0, unknownCacheRequests == 0, inputTokens > 0 else { return nil }
        return Double(cachedInputTokens) / Double(inputTokens)
    }

    public init(
        requests: Int64 = 0, inputTokens: Int64 = 0, cachedInputTokens: Int64 = 0,
        outputTokens: Int64 = 0, unknownCacheRequests: Int64 = 0,
        cacheWriteInputTokens: Int64? = nil, reasoningOutputTokens: Int64? = nil, totalTokens: Int64? = nil
    ) {
        self.requests = requests
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.unknownCacheRequests = unknownCacheRequests
        self.cacheWriteInputTokens = cacheWriteInputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.totalTokens = totalTokens
    }
}

public struct SessionSummary: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let model: String
    public let totals: UsageTotals

    public init(id: String, model: String, totals: UsageTotals) {
        self.id = id
        self.model = model
        self.totals = totals
    }
}

public enum SessionRelationshipKind: String, Codable, Sendable {
    case subagent
    case unknown
}

public struct SessionRelationship: Codable, Equatable, Sendable {
    public let kind: SessionRelationshipKind
    public let parentSessionID: String?

    public init(kind: SessionRelationshipKind, parentSessionID: String?) {
        self.kind = kind
        self.parentSessionID = parentSessionID
    }
}

public struct SessionProvenance: Codable, Equatable, Sendable {
    public let sessionID: String
    public let rootSessionID: String?
    public let displayName: String?
    public let agentPath: String?
    public let originator: String?
    public let clientVersion: String?
    public let modelProvider: String?
    public let models: [String]
    public let efforts: [String]
    public let relationship: SessionRelationship?

    public init(
        sessionID: String, rootSessionID: String? = nil, displayName: String? = nil,
        agentPath: String? = nil, originator: String? = nil, clientVersion: String? = nil,
        modelProvider: String? = nil, models: [String] = [], efforts: [String] = [],
        relationship: SessionRelationship? = nil
    ) {
        self.sessionID = sessionID
        self.rootSessionID = rootSessionID
        self.displayName = displayName
        self.agentPath = agentPath
        self.originator = originator
        self.clientVersion = clientVersion
        self.modelProvider = modelProvider
        self.models = models
        self.efforts = efforts
        self.relationship = relationship
    }
}

/// Presentation state for a session's relationship in the explicit provenance tree.
public enum SessionTreeState: String, Codable, Sendable {
    case knownRoot
    case attached
    case unknown
    case orphan
    case conflict
    case cycle
}

/// A relationship tree node. Children are structural only; their totals remain their own.
public struct SessionTreeNode: Codable, Equatable, Identifiable, Sendable {
    public let session: SessionSummary
    public let state: SessionTreeState
    public let children: [SessionTreeNode]

    public var id: String { session.id }
    public var outlineChildren: [SessionTreeNode]? { children.isEmpty ? nil : children }

    public init(session: SessionSummary, state: SessionTreeState, children: [SessionTreeNode] = []) {
        self.session = session
        self.state = state
        self.children = children
    }
}

public struct UsageReport: Codable, Equatable, Sendable {
    public let totals: UsageTotals
    public let sessions: [SessionSummary]
    public let diagnostics: [String: Int64]

    public init(totals: UsageTotals, sessions: [SessionSummary], diagnostics: [String: Int64]) {
        self.totals = totals
        self.sessions = sessions
        self.diagnostics = diagnostics
    }
}

public struct ImportSummary: Codable, Equatable, Sendable {
    public let files: Int
    public let records: Int
    public let diagnostics: [String: Int64]
    public let ioMetrics: ImportIO

    public init(files: Int, records: Int, diagnostics: [String: Int64], ioMetrics: ImportIO = ImportIO()) {
        self.files = files
        self.records = records
        self.diagnostics = diagnostics
        self.ioMetrics = ioMetrics
    }
}

public struct UsageRecord: Codable, Equatable, Sendable {
    public let responseID: String
    public let sessionID: String
    public let turnID: String
    public let timestamp: Date
    public let model: String
    public let inputTokens: Int64
    public let cachedInputTokens: Int64?
    public let outputTokens: Int64
    public let sourceLine: Int
    public let cacheWriteInputTokens: Int64?
    public let reasoningOutputTokens: Int64?
    public let totalTokens: Int64?

    public init(
        responseID: String, sessionID: String, turnID: String, timestamp: Date,
        model: String, inputTokens: Int64, cachedInputTokens: Int64?, outputTokens: Int64, sourceLine: Int,
        cacheWriteInputTokens: Int64? = nil, reasoningOutputTokens: Int64? = nil, totalTokens: Int64? = nil
    ) {
        self.responseID = responseID
        self.sessionID = sessionID
        self.turnID = turnID
        self.timestamp = timestamp
        self.model = model
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.sourceLine = sourceLine
        self.cacheWriteInputTokens = cacheWriteInputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.totalTokens = totalTokens
    }
}

/// A delta derived from a legacy cumulative `event_msg/token_count` snapshot.
/// It is deliberately not a `UsageRecord`: legacy snapshots have no stable
/// response or turn identity and are never included in canonical accounting.
public struct LegacyUsageEstimate: Codable, Equatable, Sendable {
    public let source: String?
    public let sessionID: String?
    public let timestamp: Date
    public let sourceLine: Int
    public let inputTokens: Int64
    public let cachedInputTokens: Int64?
    public let outputTokens: Int64
    public let cacheWriteInputTokens: Int64?
    public let reasoningOutputTokens: Int64?
    public let totalTokens: Int64

    public init(source: String? = nil, sessionID: String?, timestamp: Date, sourceLine: Int, inputTokens: Int64,
                cachedInputTokens: Int64?, outputTokens: Int64, cacheWriteInputTokens: Int64?,
                reasoningOutputTokens: Int64?, totalTokens: Int64) {
        self.source = source
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.sourceLine = sourceLine
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.cacheWriteInputTokens = cacheWriteInputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.totalTokens = totalTokens
    }
}

public struct ParsedRollout: Sendable {
    public var records: [UsageRecord] = []
    public var legacyEstimates: [LegacyUsageEstimate] = []
    public var timelineEvents: [TimelineSourceEvent] = []
    public var usageLimitSnapshots: [UsageLimitSnapshotObservation] = []
    public var diagnostics: [String: Int64] = [:]
    public var provenance: SessionProvenance?

    public init() {}
}
