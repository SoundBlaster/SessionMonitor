import Foundation
import MonitorCore
import SpecificationCore

/// Tunable thresholds for the bounded anomaly policies in SM-308c.
public struct AnomalyPolicyConfiguration: Equatable, Sendable {
    public let minimumPollingPairs: Int
    public let pollingPairWindow: TimeInterval
    public let startupMultiplier: Double
    public let minimumCacheSamples: Int
    public let cacheChangeRatio: Double

    public init(
        minimumPollingPairs: Int = 3, pollingPairWindow: TimeInterval = 60,
        startupMultiplier: Double = 2, minimumCacheSamples: Int = 2,
        cacheChangeRatio: Double = 0.5
    ) {
        self.minimumPollingPairs = minimumPollingPairs
        self.pollingPairWindow = pollingPairWindow
        self.startupMultiplier = startupMultiplier
        self.minimumCacheSamples = minimumCacheSamples
        self.cacheChangeRatio = cacheChangeRatio
    }
}

/// Inputs for one independent policy evaluation. Timeline events are evidence only.
public struct AnomalyPolicyContext: Sendable {
    public let session: SessionSummary
    public let timeline: RequestTimeline

    public init(session: SessionSummary, timeline: RequestTimeline) {
        self.session = session
        self.timeline = timeline
    }
}

private enum AnomalyPolicySupport {
    static func requestPoints(_ context: AnomalyPolicyContext) -> [RequestTimelinePoint] {
        context.timeline.points.filter { $0.kind == .usageRequest }.sorted { $0.timestamp < $1.timestamp }
    }

    static func pollingPoints(_ context: AnomalyPolicyContext) -> [RequestTimelinePoint] {
        context.timeline.points.filter { point in
            switch point.activityClass {
            case .wait, .waitThreads: return true
            case .processWait, .clockSleep, .goalContinuation, .shell, .unknown: return false
            case nil: return point.kind == .wait
            }
        }.sorted { $0.timestamp < $1.timestamp }
    }

    static func pollingPairs(
        _ context: AnomalyPolicyContext, configuration: AnomalyPolicyConfiguration
    ) -> [(wait: RequestTimelinePoint, request: RequestTimelinePoint)] {
        let waits = pollingPoints(context)
        let requests = requestPoints(context)
        var requestIndex = 0
        var pairs: [(wait: RequestTimelinePoint, request: RequestTimelinePoint)] = []
        for wait in waits {
            while requestIndex < requests.count && requests[requestIndex].timestamp < wait.timestamp {
                requestIndex += 1
            }
            guard requestIndex < requests.count,
                  requests[requestIndex].timestamp.timeIntervalSince(wait.timestamp)
                    <= configuration.pollingPairWindow else { continue }
            pairs.append((wait, requests[requestIndex]))
            requestIndex += 1
        }
        return pairs
    }

    static func inputTokens(_ point: RequestTimelinePoint) -> Int64? {
        guard let cached = point.cachedInputTokens, let uncached = point.uncachedInputTokens else { return nil }
        return cached + uncached
    }

    static func cacheRatio(_ point: RequestTimelinePoint) -> Double? {
        guard let input = inputTokens(point), input > 0, let cached = point.cachedInputTokens else { return nil }
        return Double(cached) / Double(input)
    }

    static func median(_ values: [Int64]) -> Double? {
        guard !values.isEmpty else { return nil }
        if values.count % 2 == 1 { return Double(values[values.count / 2]) }
        let upper = values.count / 2
        return Double(values[upper - 1] + values[upper]) / 2
    }

    static func percentage(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
}

private struct HasRequestSamplesSpec: Specification {
    let minimum: Int

    func isSatisfiedBy(_ candidate: AnomalyPolicyContext) -> Bool {
        AnomalyPolicySupport.requestPoints(candidate).count >= minimum
    }
}

private struct HasPollingPairsSpec: Specification {
    let configuration: AnomalyPolicyConfiguration

    func isSatisfiedBy(_ candidate: AnomalyPolicyContext) -> Bool {
        AnomalyPolicySupport.pollingPairs(candidate, configuration: configuration).count
            >= configuration.minimumPollingPairs
    }
}

private struct HasKnownCacheSamplesSpec: Specification {
    let minimum: Int

    func isSatisfiedBy(_ candidate: AnomalyPolicyContext) -> Bool {
        AnomalyPolicySupport.requestPoints(candidate).filter { point in
            AnomalyPolicySupport.inputTokens(point).map { $0 > 0 } == true && point.cachedInputTokens != nil
        }.count >= minimum
    }
}

private struct HasCacheChangeSpec: Specification {
    let configuration: AnomalyPolicyConfiguration

    func isSatisfiedBy(_ candidate: AnomalyPolicyContext) -> Bool {
        let known = AnomalyPolicySupport.requestPoints(candidate).filter { point in
            AnomalyPolicySupport.inputTokens(point).map { $0 > 0 } == true && point.cachedInputTokens != nil
        }
        return zip(known, known.dropFirst()).contains { before, after in
            guard let beforeRatio = AnomalyPolicySupport.cacheRatio(before),
                  let afterRatio = AnomalyPolicySupport.cacheRatio(after) else { return false }
            return abs(afterRatio - beforeRatio) >= configuration.cacheChangeRatio
        }
    }
}

public struct RepetitivePollingSpec: Specification {
    public let configuration: AnomalyPolicyConfiguration

    public init(configuration: AnomalyPolicyConfiguration = .init()) {
        self.configuration = configuration
    }

    public func isSatisfiedBy(_ candidate: AnomalyPolicyContext) -> Bool {
        HasRequestSamplesSpec(minimum: configuration.minimumPollingPairs)
            .and(HasPollingPairsSpec(configuration: configuration))
            .isSatisfiedBy(candidate)
    }
}

public struct ExcessiveStartupSpec: Specification {
    public let configuration: AnomalyPolicyConfiguration

    public init(configuration: AnomalyPolicyConfiguration = .init()) {
        self.configuration = configuration
    }

    public func isSatisfiedBy(_ candidate: AnomalyPolicyContext) -> Bool {
        let requests = AnomalyPolicySupport.requestPoints(candidate)
        guard requests.count >= 3, let firstTurn = requests.first?.turnID else { return false }
        let firstTurnRequests = Array(requests.prefix { $0.turnID == firstTurn })
        let laterRequests = Array(requests.dropFirst(firstTurnRequests.count))
        guard firstTurnRequests.count >= 2, !laterRequests.isEmpty else { return false }
        guard let baseline = AnomalyPolicySupport.median(laterRequests.compactMap(AnomalyPolicySupport.inputTokens)),
              baseline > 0 else { return false }
        let startupInputs = firstTurnRequests.compactMap(AnomalyPolicySupport.inputTokens)
        guard !startupInputs.isEmpty else { return false }
        let startupAverage = Double(startupInputs.reduce(0, +)) / Double(startupInputs.count)
        return startupAverage >= baseline * configuration.startupMultiplier
    }
}

public struct UnusualCacheChangeSpec: Specification {
    public let configuration: AnomalyPolicyConfiguration

    public init(configuration: AnomalyPolicyConfiguration = .init()) {
        self.configuration = configuration
    }

    public func isSatisfiedBy(_ candidate: AnomalyPolicyContext) -> Bool {
        HasKnownCacheSamplesSpec(minimum: configuration.minimumCacheSamples)
            .and(HasCacheChangeSpec(configuration: configuration))
            .isSatisfiedBy(candidate)
    }
}

public struct RepetitivePollingDecision: DecisionSpec {
    public typealias Context = AnomalyPolicyContext
    public typealias Result = AnomalyFinding

    public let configuration: AnomalyPolicyConfiguration

    public init(configuration: AnomalyPolicyConfiguration = .init()) {
        self.configuration = configuration
    }

    public func decide(_ context: Context) -> Result? {
        guard RepetitivePollingSpec(configuration: configuration).isSatisfiedBy(context) else { return nil }
        let pairs = AnomalyPolicySupport.pollingPairs(context, configuration: configuration)
        let waitLines = pairs.compactMap { $0.wait.sourceLine }.sorted()
        let responseIDs = pairs.compactMap { $0.request.responseID }.sorted()
        return AnomalyFinding(
            kind: .repetitivePolling, title: "Repetitive polling",
            reason: "Explicit wait events repeatedly precede usage requests in a short interval.", severity: .warning,
            evidence: DiagnosticEvidence(
                observed: [DiagnosticEvidenceItem(
                    source: "source_timeline_events",
                    detail: "\(pairs.count) wait-to-request pairs were observed within "
                        + "\(Int(configuration.pollingPairWindow)) seconds.",
                    sessionIDs: [context.session.id], responseIDs: responseIDs, sourceLines: waitLines
                )],
                inference: [
                    DiagnosticEvidenceItem(
                        source: "diagnostic_heuristic",
                        detail: "The repeated wait/request sequence is classified as polling-like.",
                        sessionIDs: [context.session.id]
                    ),
                    DiagnosticEvidenceItem(
                        source: "specification_core_policy",
                        detail: "RepetitivePollingSpec and its composed sample/window rules are satisfied.",
                        sessionIDs: [context.session.id]
                    )
                ],
                unknown: [DiagnosticEvidenceItem(
                    source: "source_timeline_events",
                    detail: "The source does not establish whether the polling was intentional.",
                    sessionIDs: [context.session.id]
                )], limitations: ["A single or normally long wait is not classified as polling."]
            ), confidence: .medium, coverage: .observed, affectedSessions: [context.session.id],
            suggestedNextAction: "Inspect the wait cadence and add backoff or event-driven completion if the polling "
                + "is unintentional."
        )
    }
}

public struct AnomalyPolicyEngine {
    private let decisions: [AnyDecisionSpec<AnomalyPolicyContext, AnomalyFinding>]

    public init(configuration: AnomalyPolicyConfiguration = .init()) {
        decisions = [
            AnyDecisionSpec(RepetitivePollingDecision(configuration: configuration)),
            AnyDecisionSpec(ExcessiveStartupDecision(configuration: configuration)),
            AnyDecisionSpec(UnusualCacheChangeDecision(configuration: configuration))
        ]
    }

    /// Evaluates every independent rule; no first-match short circuit hides co-occurring signals.
    public func evaluate(_ context: AnomalyPolicyContext) -> [AnomalyFinding] {
        decisions.compactMap { $0.decide(context) }.sorted { $0.id < $1.id }
    }
}

public extension AnomalyFinding {
    /// Adapts policy output to the existing doctor/CLI report contract.
    func asDiagnosticFinding() -> DiagnosticFinding {
        DiagnosticFinding(
            id: id, severity: severity, title: title, explanation: reason,
            evidence: evidence, confidence: confidence, affectedSessions: affectedSessions,
            suggestedNextAction: suggestedNextAction
        )
    }
}

private struct ExcessiveStartupDecision: DecisionSpec {
    typealias Context = AnomalyPolicyContext
    typealias Result = AnomalyFinding

    let configuration: AnomalyPolicyConfiguration

    func decide(_ context: Context) -> Result? {
        guard ExcessiveStartupSpec(configuration: configuration).isSatisfiedBy(context) else { return nil }
        let requests = AnomalyPolicySupport.requestPoints(context)
        let firstTurn = requests[0].turnID
        let firstTurnRequests = Array(requests.prefix { $0.turnID == firstTurn })
        let laterRequests = Array(requests.dropFirst(firstTurnRequests.count))
        let baseline = AnomalyPolicySupport.median(laterRequests.compactMap(AnomalyPolicySupport.inputTokens)) ?? 0
        let startupInputs = firstTurnRequests.compactMap(AnomalyPolicySupport.inputTokens)
        let startupAverage = Double(startupInputs.reduce(0, +)) / Double(startupInputs.count)
        let startupResponses = firstTurnRequests.compactMap(\.responseID).sorted()
        return AnomalyFinding(
            kind: .startupOverhead, title: "Excessive startup overhead",
            reason: "Multiple requests in the first observed turn have substantially larger input than later requests.",
            severity: .warning,
            evidence: DiagnosticEvidence(
                observed: [DiagnosticEvidenceItem(
                    source: "confirmed",
                    detail: "First-turn average input (\(Int(startupAverage))) is at least "
                        + "\(configuration.startupMultiplier)x the later-request median (\(Int(baseline))).",
                    sessionIDs: [context.session.id], responseIDs: startupResponses
                )],
                inference: [
                    DiagnosticEvidenceItem(
                        source: "diagnostic_heuristic",
                        detail: "The repeated first-turn input is classified as startup overhead.",
                        sessionIDs: [context.session.id]
                    ),
                    DiagnosticEvidenceItem(
                        source: "specification_core_policy",
                        detail: "ExcessiveStartupSpec satisfied the repeated-first-turn and baseline rules.",
                        sessionIDs: [context.session.id]
                    )
                ],
                unknown: [DiagnosticEvidenceItem(
                    source: "confirmed",
                    detail: "The source does not identify whether the startup work was necessary.",
                    sessionIDs: [context.session.id]
                )], limitations: ["One first request alone is not classified as startup overhead."]
            ), confidence: .medium, coverage: .observed, affectedSessions: [context.session.id],
            suggestedNextAction: "Inspect the first-turn request sequence for duplicate initialization or "
                + "avoidable context loading."
        )
    }
}

private struct UnusualCacheChangeDecision: DecisionSpec {
    typealias Context = AnomalyPolicyContext
    typealias Result = AnomalyFinding

    let configuration: AnomalyPolicyConfiguration

    // swiftlint:disable:next function_body_length
    func decide(_ context: Context) -> Result? {
        guard UnusualCacheChangeSpec(configuration: configuration).isSatisfiedBy(context) else { return nil }
        let known = AnomalyPolicySupport.requestPoints(context).filter { point in
            AnomalyPolicySupport.inputTokens(point).map { $0 > 0 } == true && point.cachedInputTokens != nil
        }
        var largest: CacheChangeCandidate?
        for pair in zip(known, known.dropFirst()) {
            guard let before = AnomalyPolicySupport.cacheRatio(pair.0),
                  let after = AnomalyPolicySupport.cacheRatio(pair.1) else { continue }
            let change = abs(after - before)
            if change >= configuration.cacheChangeRatio, largest.map({ change > $0.change }) ?? true {
                largest = CacheChangeCandidate(before: pair.0, after: pair.1, change: change)
            }
        }
        guard let largest, let before = AnomalyPolicySupport.cacheRatio(largest.before),
              let after = AnomalyPolicySupport.cacheRatio(largest.after) else { return nil }
        let unknownRequests = context.timeline.points.filter {
            $0.kind == .usageRequest && $0.cachedInputTokens == nil
        }.count
        let unknown: [DiagnosticEvidenceItem] = unknownRequests > 0 ? [DiagnosticEvidenceItem(
            source: "confirmed",
            detail: "\(unknownRequests) request(s) with unknown cache were excluded from the comparison.",
            sessionIDs: [context.session.id]
        )] : []
        let coverage: AnomalyCoverage = unknownRequests > 0
            ? .partial(reason: "Some request cache values were unknown and excluded from comparison.")
            : .observed
        return AnomalyFinding(
            kind: .cacheDrop, title: "Unusual cache changes",
            reason: "Known cache coverage changes sharply between adjacent observed requests.", severity: .warning,
            evidence: DiagnosticEvidence(
                observed: [DiagnosticEvidenceItem(
                    source: "confirmed",
                    detail: "Cache ratio changed from \(AnomalyPolicySupport.percentage(before)) to "
                        + "\(AnomalyPolicySupport.percentage(after)).",
                    sessionIDs: [context.session.id],
                    responseIDs: [largest.before.responseID, largest.after.responseID].compactMap { $0 }
                )],
                inference: [
                    DiagnosticEvidenceItem(
                        source: "diagnostic_heuristic",
                        detail: "The absolute cache-ratio change exceeds the configured threshold.",
                        sessionIDs: [context.session.id]
                    ),
                    DiagnosticEvidenceItem(
                        source: "specification_core_policy",
                        detail: "UnusualCacheChangeSpec satisfied the known-sample and change-ratio rules.",
                        sessionIDs: [context.session.id]
                    )
                ], unknown: unknown,
                limitations: ["Unknown cache values are excluded and are never treated as a zero cache hit."]
            ), confidence: .medium, coverage: coverage, affectedSessions: [context.session.id],
            suggestedNextAction: "Inspect the adjacent requests and verify whether the cache boundary reflects "
                + "a real context change."
        )
    }
}

private struct CacheChangeCandidate {
    let before: RequestTimelinePoint
    let after: RequestTimelinePoint
    let change: Double
}
