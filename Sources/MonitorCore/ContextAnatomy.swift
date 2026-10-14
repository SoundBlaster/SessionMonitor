import Foundation

/// Coarse fill band of a request relative to its `ContextFillBasis`. Presentation only.
public enum ContextFillZone: String, Codable, CaseIterable, Sendable {
    case low
    case moderate
    case high
    case critical
}

/// Reference for fill fractions (SM-727).
public enum ContextFillBasis: String, Codable, CaseIterable, Sendable {
    /// Share of the usable context window the source reported (model window minus its reserved headroom).
    case modelWindow
    /// Share of the session's own peak request input; used only when no request reported a window.
    case sessionPeak
}

/// Counts of non-request timeline events between two requests; presentation evidence only.
public struct ContextActivitySummary: Codable, Equatable, Sendable {
    public var tools: Int
    public var waits: Int
    public var humanTurns: Int
    public var goalTurns: Int
    public var compactions: Int
    /// Events with kind `.unknown`.
    public var other: Int

    public static let none = ContextActivitySummary()

    public init(tools: Int = 0, waits: Int = 0, humanTurns: Int = 0, goalTurns: Int = 0,
                compactions: Int = 0, other: Int = 0) {
        self.tools = tools
        self.waits = waits
        self.humanTurns = humanTurns
        self.goalTurns = goalTurns
        self.compactions = compactions
        self.other = other
    }

    public var isEmpty: Bool { self == .none }

    mutating func add(_ kind: TimelineEventKind) {
        switch kind {
        case .usageRequest: break
        case .tool: tools += 1
        case .wait: waits += 1
        case .humanTurn: humanTurns += 1
        case .goalTurn: goalTurns += 1
        case .compaction: compactions += 1
        case .unknown: other += 1
        }
    }
}

/// One request in the context-growth chart. Unknown values stay nil and are never counted as zero.
public struct ContextAnatomyStep: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    /// 1-based position among steps.
    public let index: Int
    public let timestamp: Date
    public let model: String?
    /// Canonical request input, which includes cached input.
    public let contextTokens: Int64
    public let cachedInputTokens: Int64?
    /// Input minus cached input; nil when the cache split is unknown.
    public let newInputTokens: Int64?
    public let outputTokens: Int64?
    public let reasoningOutputTokens: Int64?
    public let cacheWriteInputTokens: Int64?
    /// Change of context versus the previous step; nil for the first step and negative after shrinkage.
    public let deltaFromPrevious: Int64?
    /// Running input plus output; nil from the first step with unknown output onward.
    public let cumulativeTokens: Int64?
    /// Share of the anatomy's basis: `contextWindowTokens`, or the session peak (0 when the peak is 0).
    public let fillFraction: Double
    public let zone: ContextFillZone
    /// Usable window the fraction is taken of; nil under the session-peak basis.
    public let contextWindowTokens: Int64?
    /// True when this request reported no window and borrowed the nearest one of the session.
    public let contextWindowInferred: Bool
    public let activityBefore: ContextActivitySummary
}

/// Presentation evidence derived from a request timeline; never part of canonical accounting.
public struct ContextAnatomy: Codable, Equatable, Sendable {
    public let sessionID: String
    public let steps: [ContextAnatomyStep]
    public let peakContextTokens: Int64
    public let basis: ContextFillBasis
    /// Events after the last request step.
    public let trailingActivity: ContextActivitySummary
    /// Usage requests skipped because their input is unknown.
    public let requestsWithUnknownInput: Int

    public init(sessionID: String, steps: [ContextAnatomyStep], peakContextTokens: Int64,
                basis: ContextFillBasis = .sessionPeak, trailingActivity: ContextActivitySummary,
                requestsWithUnknownInput: Int) {
        self.sessionID = sessionID
        self.steps = steps
        self.peakContextTokens = peakContextTokens
        self.basis = basis
        self.trailingActivity = trailingActivity
        self.requestsWithUnknownInput = requestsWithUnknownInput
    }

    public var isEmpty: Bool { steps.isEmpty }
}

public enum ContextAnatomyBuilder {
    /// Builds steps from usage-request points in the given order; other points become activity counts.
    public static func build(_ timeline: RequestTimeline) -> ContextAnatomy {
        var requests: [PendingRequest] = []
        var pending = ContextActivitySummary.none
        var unknownInput = 0
        for point in timeline.points {
            guard point.kind == .usageRequest else {
                pending.add(point.kind)
                continue
            }
            guard let input = point.inputTokens else {
                unknownInput += 1
                continue
            }
            requests.append(PendingRequest(point: point, input: input, activity: pending))
            pending = .none
        }
        let peak = requests.map(\.input).max() ?? 0
        let windows = resolvedWindows(requests.map(\.point.contextWindowTokens))
        let basis: ContextFillBasis = windows.contains { $0 != nil } ? .modelWindow : .sessionPeak
        return ContextAnatomy(
            sessionID: timeline.sessionID, steps: makeSteps(requests, peak: peak, windows: windows),
            peakContextTokens: peak, basis: basis, trailingActivity: pending, requestsWithUnknownInput: unknownInput
        )
    }

    /// Each request keeps its own reported window. A request without one borrows the nearest earlier window
    /// of the session, or the nearest later one before any window is known; nil only when none is known.
    static func resolvedWindows(_ reported: [Int64?]) -> [(tokens: Int64, inferred: Bool)?] {
        var resolved: [(tokens: Int64, inferred: Bool)?] = []
        var previous: Int64?
        for window in reported {
            if let window { previous = window }
            resolved.append(window.map { ($0, false) } ?? previous.map { ($0, true) })
        }
        var next: Int64?
        for offset in resolved.indices.reversed() {
            if let window = reported[offset] { next = window }
            if resolved[offset] == nil { resolved[offset] = next.map { ($0, true) } }
        }
        return resolved
    }

    /// low < 0.5, moderate < 0.75, high < 0.9, critical otherwise.
    public static func zone(forFraction fraction: Double) -> ContextFillZone {
        if fraction < 0.5 { return .low }
        if fraction < 0.75 { return .moderate }
        if fraction < 0.9 { return .high }
        return .critical
    }

    private struct PendingRequest {
        let point: RequestTimelinePoint
        let input: Int64
        let activity: ContextActivitySummary
    }

    private static func makeSteps(_ requests: [PendingRequest], peak: Int64,
                                  windows: [(tokens: Int64, inferred: Bool)?]) -> [ContextAnatomyStep] {
        var steps: [ContextAnatomyStep] = []
        var previousInput: Int64?
        var cumulative: Int64? = 0
        for (offset, request) in requests.enumerated() {
            let point = request.point
            let input = request.input
            cumulative = point.outputTokens.flatMap { output in cumulative.map { $0 + input + output } }
            // Under the window basis every step has a window; otherwise all share the session peak.
            let window = windows[offset]
            let reference = window?.tokens ?? peak
            let fraction = reference > 0 ? Double(input) / Double(reference) : 0
            steps.append(ContextAnatomyStep(
                id: point.id, index: offset + 1, timestamp: point.timestamp, model: point.model,
                contextTokens: input, cachedInputTokens: point.cachedInputTokens,
                newInputTokens: point.cachedInputTokens.map { input - $0 },
                outputTokens: point.outputTokens, reasoningOutputTokens: point.reasoningOutputTokens,
                cacheWriteInputTokens: point.cacheWriteInputTokens,
                deltaFromPrevious: previousInput.map { input - $0 }, cumulativeTokens: cumulative,
                fillFraction: fraction, zone: zone(forFraction: fraction),
                contextWindowTokens: window?.tokens, contextWindowInferred: window?.inferred ?? false,
                activityBefore: request.activity
            ))
            previousInput = input
        }
        return steps
    }
}
