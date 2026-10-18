import Foundation

/// Presentation-only signals. They do not change accounting or assert the cause of a cache miss/reset.
public enum ContextInsightKind: String, Codable, CaseIterable, Sendable {
    case contextGrowth
    case contextDrop
    case compaction
    case coldStart
    case cacheDropAfterPause
    case criticalEntry
}

public struct ContextInsight: Codable, Equatable, Identifiable, Sendable {
    public let kind: ContextInsightKind
    public let requestID: String
    public let requestIndex: Int
    public let title: String
    public let explanation: String
    public let evidence: DiagnosticEvidence
    public let isHypothesis: Bool

    public var id: String { "\(kind.rawValue):\(requestID)" }

    public init(kind: ContextInsightKind, step: ContextAnatomyStep, title: String, explanation: String,
                evidence: DiagnosticEvidence, isHypothesis: Bool = false) {
        self.kind = kind
        requestID = step.id
        requestIndex = step.index
        self.title = title
        self.explanation = explanation
        self.evidence = evidence
        self.isHypothesis = isHypothesis
    }
}

/// A contiguous run in one zone. Token sums are request volume, not unique context content.
public struct ContextInsightPhase: Codable, Equatable, Identifiable, Sendable {
    public let zone: ContextFillZone
    public let firstRequestID: String
    public let firstIndex: Int
    public let lastIndex: Int
    public let requests: Int
    /// Nil after overflow, never wrapped or clamped into an apparently exact value.
    public let inputTokens: Int64?
    /// Nil when any request in the phase has unknown output, or the sum overflows.
    public let outputTokens: Int64?
    public var id: String { firstRequestID }

    public init(zone: ContextFillZone, firstRequestID: String, firstIndex: Int, lastIndex: Int,
                requests: Int, inputTokens: Int64?, outputTokens: Int64?) {
        self.zone = zone
        self.firstRequestID = firstRequestID
        self.firstIndex = firstIndex
        self.lastIndex = lastIndex
        self.requests = requests
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

public struct ContextInsightReport: Equatable, Sendable {
    public let query: UsageQuery
    public let anatomy: ContextAnatomy
    public let insights: [ContextInsight]
    public let phases: [ContextInsightPhase]
    public let limitations: [String]
    /// Pre-indexed once at report construction; pointer movement never scans the report.
    public let insightsByRequest: [Int: [ContextInsight]]

    public init(query: UsageQuery, anatomy: ContextAnatomy, insights: [ContextInsight], phases: [ContextInsightPhase],
                limitations: [String]) {
        self.query = query
        self.anatomy = anatomy
        self.insights = insights
        self.phases = phases
        self.limitations = limitations
        insightsByRequest = Dictionary(grouping: insights, by: \.requestIndex)
    }
}
