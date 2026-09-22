import Foundation
import MonitorCore
import SpecificationCore

/// Tunable thresholds for the bounded anomaly policies in SM-308c.
public struct AnomalyPolicyConfiguration: Equatable, Sendable {
    public let minimumPollingPairs: Int
    public let pollingPairWindow: TimeInterval
    public let pollingSequenceWindow: TimeInterval
    public let startupMultiplier: Double
    public let minimumStartupSamples: Int
    public let minimumCacheSamples: Int
    public let cacheChangeRatio: Double
    public let minimumCacheInputTokens: Int64
    public let cacheComparisonWindow: TimeInterval
    public let minimumAbsoluteInputTokens: Int64
    public let minimumAbsoluteRequests: Int64
    public let dominantSessionShare: Double
    public let minimumDominantInputTokens: Int64
    public let minimumUncachedInputTokens: Int64

    public init(
        minimumPollingPairs: Int = 3, pollingPairWindow: TimeInterval = 60,
        pollingSequenceWindow: TimeInterval = 300, startupMultiplier: Double = 2, minimumStartupSamples: Int = 2,
        minimumCacheSamples: Int = 2, cacheChangeRatio: Double = 0.5,
        minimumCacheInputTokens: Int64 = 1_000, cacheComparisonWindow: TimeInterval = 3_600,
        minimumAbsoluteInputTokens: Int64 = 50_000_000, minimumAbsoluteRequests: Int64 = 500,
        dominantSessionShare: Double = 0.5, minimumDominantInputTokens: Int64 = 10_000_000,
        minimumUncachedInputTokens: Int64 = 1_000_000
    ) {
        self.minimumPollingPairs = max(1, minimumPollingPairs)
        self.pollingPairWindow = Self.validWindow(pollingPairWindow, fallback: 60)
        self.pollingSequenceWindow = Self.validWindow(pollingSequenceWindow, fallback: 300)
        self.startupMultiplier = Self.validPositive(startupMultiplier, fallback: 2)
        self.minimumStartupSamples = max(2, minimumStartupSamples)
        self.minimumCacheSamples = max(2, minimumCacheSamples)
        self.cacheChangeRatio = min(max(cacheChangeRatio.isFinite ? cacheChangeRatio : 0.5, 0.01), 1)
        self.minimumCacheInputTokens = max(1, minimumCacheInputTokens)
        self.cacheComparisonWindow = Self.validWindow(cacheComparisonWindow, fallback: 3_600)
        self.minimumAbsoluteInputTokens = max(1, minimumAbsoluteInputTokens)
        self.minimumAbsoluteRequests = max(1, minimumAbsoluteRequests)
        self.dominantSessionShare = min(max(dominantSessionShare.isFinite ? dominantSessionShare : 0.5, 0.01), 1)
        self.minimumDominantInputTokens = max(1, minimumDominantInputTokens)
        self.minimumUncachedInputTokens = max(1, minimumUncachedInputTokens)
    }

    private static func validWindow(_ value: TimeInterval, fallback: TimeInterval) -> TimeInterval {
        value.isFinite && value > 0 ? value : fallback
    }

    private static func validPositive(_ value: Double, fallback: Double) -> Double {
        value.isFinite && value > 0 ? value : fallback
    }
}

/// Inputs for one independent policy evaluation. Timeline events are evidence only.
public struct AnomalyPolicyContext: Sendable {
    public let session: SessionSummary
    public let timeline: RequestTimeline
    public let cohort: [SessionSummary]

    public init(session: SessionSummary, timeline: RequestTimeline, cohort: [SessionSummary] = []) {
        self.session = session
        self.timeline = timeline
        self.cohort = cohort.isEmpty ? [session] : cohort
    }
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
        !AnomalyPolicySupport.comparableCachePairs(candidate, configuration: configuration).isEmpty
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
        guard firstTurnRequests.count >= configuration.minimumStartupSamples,
              !laterRequests.isEmpty else { return false }
        guard let baseline = AnomalyPolicySupport.median(laterRequests.compactMap(AnomalyPolicySupport.inputTokens)),
              baseline > 0 else { return false }
        let startupInputs = firstTurnRequests.compactMap(AnomalyPolicySupport.inputTokens)
        guard startupInputs.count >= configuration.minimumStartupSamples else { return false }
        let startupAverage = startupInputs.map(Double.init).reduce(0, +) / Double(startupInputs.count)
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
            AnyDecisionSpec(UnusualCacheChangeDecision(configuration: configuration, direction: .drop)),
            AnyDecisionSpec(UnusualCacheChangeDecision(configuration: configuration, direction: .recovery)),
            AnyDecisionSpec(HighAbsoluteUsageDecision(configuration: configuration)),
            AnyDecisionSpec(DominantSessionDecision(configuration: configuration)),
            AnyDecisionSpec(UncachedBurstDecision(configuration: configuration))
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
            suggestedNextAction: suggestedNextAction, coverage: coverage
        )
    }
}

private struct ExcessiveStartupDecision: DecisionSpec {
    typealias Context = AnomalyPolicyContext
    typealias Result = AnomalyFinding

    let configuration: AnomalyPolicyConfiguration

    // swiftlint:disable:next function_body_length
    func decide(_ context: Context) -> Result? {
        guard ExcessiveStartupSpec(configuration: configuration).isSatisfiedBy(context) else { return nil }
        let requests = AnomalyPolicySupport.requestPoints(context)
        let firstTurn = requests[0].turnID
        let firstTurnRequests = Array(requests.prefix { $0.turnID == firstTurn })
        let laterRequests = Array(requests.dropFirst(firstTurnRequests.count))
        let baseline = AnomalyPolicySupport.median(laterRequests.compactMap(AnomalyPolicySupport.inputTokens)) ?? 0
        let startupInputs = firstTurnRequests.compactMap(AnomalyPolicySupport.inputTokens)
        let startupAverage = startupInputs.map(Double.init).reduce(0, +) / Double(startupInputs.count)
        let startupResponses = firstTurnRequests.compactMap(\.responseID).sorted()
        let unknownStartupSamples = firstTurnRequests.count - startupInputs.count
        let startupCoverage: AnomalyCoverage = unknownStartupSamples > 0
            ? .partial(reason: "Some first-turn cache values were unknown and excluded from startup comparison.")
            : .observed
        let startupUnknownEvidence = unknownStartupSamples > 0
            ? [DiagnosticEvidenceItem(
                source: "confirmed",
                detail: "\(unknownStartupSamples) first-turn request(s) with unknown cache were excluded.",
                sessionIDs: [context.session.id]
            )]
            : []
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
                unknown: startupUnknownEvidence + [DiagnosticEvidenceItem(
                    source: "confirmed",
                    detail: "The source does not identify whether the startup work was necessary.",
                    sessionIDs: [context.session.id]
                )], limitations: ["One first request alone is not classified as startup overhead."]
            ), confidence: .medium, coverage: startupCoverage, affectedSessions: [context.session.id],
            suggestedNextAction: "Inspect the first-turn request sequence for duplicate initialization or "
                + "avoidable context loading."
        )
    }
}

private struct UnusualCacheChangeDecision: DecisionSpec {
    typealias Context = AnomalyPolicyContext
    typealias Result = AnomalyFinding

    let configuration: AnomalyPolicyConfiguration
    let direction: CacheChangeDirection

    // swiftlint:disable:next function_body_length
    func decide(_ context: Context) -> Result? {
        guard UnusualCacheChangeSpec(configuration: configuration).isSatisfiedBy(context) else { return nil }
        let largest = AnomalyPolicySupport.comparableCachePairs(context, configuration: configuration)
            .filter { pair in
                guard let before = AnomalyPolicySupport.cacheRatio(pair.before),
                      let after = AnomalyPolicySupport.cacheRatio(pair.after) else { return false }
                return direction == .drop ? after < before : after > before
            }
            .max { $0.change < $1.change }
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
        let isDrop = direction == .drop
        let kind: AnomalyKind = isDrop ? .cacheDrop : .cacheRecovery
        let title = isDrop ? "Cache coverage drop" : "Cache coverage recovery"
        let reason = isDrop
            ? "Known cache coverage drops sharply between comparable observed requests."
            : "Known cache coverage recovers sharply between comparable observed requests."
        return AnomalyFinding(
            kind: kind, title: title, reason: reason, severity: isDrop ? .warning : .info,
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
                        detail: "The cache-ratio change exceeds the configured threshold for comparable requests.",
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
            suggestedNextAction: isDrop
                ? "Inspect the adjacent requests and verify whether the cache boundary reflects a real context change."
                : "Inspect the recovered cache boundary and verify whether the context became stable again."
        )
    }
}

private enum CacheChangeDirection { case drop, recovery }
