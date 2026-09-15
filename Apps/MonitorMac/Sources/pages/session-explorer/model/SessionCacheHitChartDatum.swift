import Foundation
import MonitorCore
import MonitorPolicies

/// One chart datum for one session in the current query snapshot.
///
/// The projection deliberately delegates state decisions to the shared domain policy and
/// never combines request-level percentages or recalculates report totals.
struct SessionCacheHitChartDatum: Identifiable, Equatable, Sendable {
    enum VisualState: Equatable, Sendable {
        case known
        case belowThreshold
        case unavailable

        var legendLabel: String {
            switch self {
            case .known: "Known"
            case .belowThreshold: "Below threshold"
            case .unavailable: "Unavailable"
            }
        }
    }

    let id: String
    let index: Int
    let displayName: String
    let axisLabel: String
    let policyState: CacheHitThresholdPolicy.Presentation
    let visualState: VisualState
    let cacheHitPercent: Double?
    let valueLabel: String
    let statusLabel: String
    let accessibilityLabel: String
    let accessibilityValue: String

    static func make(
        sessions: [SessionSummary],
        provenance: [String: SessionProvenance],
        policy: CacheHitThresholdPolicy
    ) -> [Self] {
        var usedAxisLabels = Set<String>()

        return sessions.enumerated().map { index, session in
            let displayName = displayName(for: session, provenance: provenance)
            let axisLabel = uniqueAxisLabel(for: displayName, usedLabels: &usedAxisLabels)
            return Self(
                index: index,
                session: session,
                displayName: displayName,
                axisLabel: axisLabel,
                policyState: policy.presentation(for: session)
            )
        }
    }

    private init(
        index: Int,
        session: SessionSummary,
        displayName: String,
        axisLabel: String,
        policyState: CacheHitThresholdPolicy.Presentation
    ) {
        id = session.id
        self.index = index
        self.displayName = displayName
        self.axisLabel = axisLabel
        self.policyState = policyState

        switch policyState {
        case let .knownBelowThreshold(cacheHitPercent, thresholdPercent):
            visualState = .belowThreshold
            self.cacheHitPercent = cacheHitPercent
            valueLabel = Self.percentLabel(cacheHitPercent)
            statusLabel = "Below threshold"
            accessibilityValue = "\(valueLabel). Below threshold of \(Self.percentLabel(thresholdPercent))."
        case let .knownAtThreshold(cacheHitPercent, thresholdPercent):
            visualState = .known
            self.cacheHitPercent = cacheHitPercent
            valueLabel = Self.percentLabel(cacheHitPercent)
            statusLabel = "At threshold"
            accessibilityValue = "\(valueLabel). At threshold of \(Self.percentLabel(thresholdPercent))."
        case let .knownAboveThreshold(cacheHitPercent, thresholdPercent):
            visualState = .known
            self.cacheHitPercent = cacheHitPercent
            valueLabel = Self.percentLabel(cacheHitPercent)
            statusLabel = "Above threshold"
            accessibilityValue = "\(valueLabel). Above threshold of \(Self.percentLabel(thresholdPercent))."
        case .unknown:
            visualState = .unavailable
            cacheHitPercent = nil
            valueLabel = "—"
            statusLabel = "Unknown cache coverage"
            accessibilityValue = "Unavailable. Unknown cache coverage."
        case let .partialCacheCoverage(unknownRequests):
            visualState = .unavailable
            cacheHitPercent = nil
            valueLabel = "—"
            statusLabel = "Partial cache coverage"
            accessibilityValue = "Unavailable. Partial cache coverage; \(unknownRequests.formatted()) unknown requests."
        case .zeroInput:
            visualState = .unavailable
            cacheHitPercent = nil
            valueLabel = "—"
            statusLabel = "Zero input tokens"
            accessibilityValue = "Unavailable. Zero input tokens."
        case .noCanonicalRequests:
            visualState = .unavailable
            cacheHitPercent = nil
            valueLabel = "—"
            statusLabel = "No canonical requests"
            accessibilityValue = "Unavailable. No canonical requests."
        }

        accessibilityLabel = "\(displayName), session \(session.id)"
    }

    private static func displayName(
        for session: SessionSummary,
        provenance: [String: SessionProvenance]
    ) -> String {
        provenance[session.id]?.displayName
            ?? (session.model.isEmpty ? "Unknown model" : session.model)
    }

    private static func uniqueAxisLabel(for displayName: String, usedLabels: inout Set<String>) -> String {
        let base = displayName.count > 22 ? String(displayName.prefix(21)) + "…" : displayName
        var label = base
        var suffix = 2
        while usedLabels.contains(label) {
            label = "\(base) #\(suffix)"
            suffix += 1
        }
        usedLabels.insert(label)
        return label
    }

    private static func percentLabel(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + "%"
    }
}
