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

/// Explicit operational classification retained as auxiliary source evidence.
public enum ActivityToolClass: String, Codable, CaseIterable, Sendable {
    case shell
    case wait
    case processWait = "process_wait"
    case waitThreads = "wait_threads"
    case clockSleep = "clock_sleep"
    case goalContinuation = "goal_continuation"
    case unknown

    /// Classifies only exact tool names observed in the supported local source contract.
    public static func classify(toolName: String?) -> ActivityToolClass {
        guard let toolName else { return .unknown }
        switch toolName {
        case "exec_command": return .shell
        case "wait": return .wait
        case "write_stdin": return .processWait
        case "wait_threads": return .waitThreads
        case "clock.sleep", "clock__sleep": return .clockSleep
        default: return .unknown
        }
    }
}

public struct TimelineSourceEvent: Codable, Equatable, Sendable {
    public let sessionID: String
    public let turnID: String?
    public let timestamp: Date
    public let sourceLine: Int
    public let kind: TimelineEventKind
    public let evidence: String
    public let toolName: String?
    public let model: String?
    public let activityClass: ActivityToolClass?

    public init(sessionID: String, turnID: String? = nil, timestamp: Date, sourceLine: Int,
                kind: TimelineEventKind, evidence: String, toolName: String? = nil,
                model: String? = nil, activityClass: ActivityToolClass? = nil) {
        self.sessionID = sessionID
        self.turnID = turnID
        self.timestamp = timestamp
        self.sourceLine = sourceLine
        self.kind = kind
        self.evidence = evidence
        self.toolName = toolName
        self.model = model
        self.activityClass = activityClass
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
    public let toolName: String?
    public let model: String?
    public let activityClass: ActivityToolClass?

    public init(id: String, sessionID: String, timestamp: Date, kind: TimelineEventKind,
                turnID: String? = nil, sourceLine: Int? = nil, responseID: String? = nil,
                cachedInputTokens: Int64? = nil, uncachedInputTokens: Int64? = nil,
                evidence: String? = nil, toolName: String? = nil, model: String? = nil,
                activityClass: ActivityToolClass? = nil) {
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
        self.toolName = toolName
        self.model = model
        self.activityClass = activityClass
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
