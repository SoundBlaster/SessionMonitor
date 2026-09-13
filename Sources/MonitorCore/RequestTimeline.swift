import Foundation

/// A semantic event is only emitted when the source contains an explicit signal.
/// It is presentation evidence and is never part of canonical usage accounting.
public enum TimelineEventKind: String, Codable, CaseIterable, Sendable {
    case usageRequest
    case humanTurn
    case goalTurn
    case compaction
    case tool
    case wait
    case unknown
}

public struct TimelineSourceEvent: Codable, Equatable, Sendable {
    public let sessionID: String
    public let turnID: String?
    public let timestamp: Date
    public let sourceLine: Int
    public let kind: TimelineEventKind
    public let evidence: String

    public init(sessionID: String, turnID: String? = nil, timestamp: Date, sourceLine: Int,
                kind: TimelineEventKind, evidence: String) {
        self.sessionID = sessionID
        self.turnID = turnID
        self.timestamp = timestamp
        self.sourceLine = sourceLine
        self.kind = kind
        self.evidence = evidence
    }
}

public struct RequestTimelinePoint: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let sessionID: String
    public let timestamp: Date
    public let kind: TimelineEventKind
    public let turnID: String?
    public let sourceLine: Int?
    public let responseID: String?
    public let cachedInputTokens: Int64?
    public let uncachedInputTokens: Int64?
    public let evidence: String?

    public init(id: String, sessionID: String, timestamp: Date, kind: TimelineEventKind,
                turnID: String? = nil, sourceLine: Int? = nil, responseID: String? = nil,
                cachedInputTokens: Int64? = nil, uncachedInputTokens: Int64? = nil,
                evidence: String? = nil) {
        self.id = id
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.kind = kind
        self.turnID = turnID
        self.sourceLine = sourceLine
        self.responseID = responseID
        self.cachedInputTokens = cachedInputTokens
        self.uncachedInputTokens = uncachedInputTokens
        self.evidence = evidence
    }
}

public struct RequestTimeline: Codable, Equatable, Sendable {
    public let sessionID: String
    public let query: UsageQuery
    public let points: [RequestTimelinePoint]

    public init(sessionID: String, query: UsageQuery, points: [RequestTimelinePoint]) {
        self.sessionID = sessionID
        self.query = query
        self.points = points
    }

    public var isEmpty: Bool { points.isEmpty }
}
