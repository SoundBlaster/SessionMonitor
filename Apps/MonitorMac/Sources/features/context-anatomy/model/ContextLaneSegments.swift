import Foundation
import MonitorCore

/// Horizontal split of one lane-strip column. Fractions are shares of the column width.
struct ContextLaneSegments: Equatable {
    /// The parts a column can show, each drawn in the colour of its token flow (SM-726).
    enum Kind {
        case newInput
        case output
        case reasoning
        case otherActivity

        var flow: UsageChartPalette.Flow {
            switch self {
            case .newInput: .input
            case .output, .reasoning: .output
            case .otherActivity: .other
            }
        }
    }

    /// New input; when the cache split is unknown this is the whole request input.
    let inputFraction: Double
    let outputFraction: Double
    /// Part of the output segment that is reasoning (never larger than `outputFraction`).
    let reasoningFraction: Double
    /// False when the cache split is unknown, so the input segment is drawn gray rather than as zero.
    let inputKnown: Bool
    let outputKnown: Bool
    /// False when output is known and positive but the source did not report reasoning tokens,
    /// so reasoning is drawn as unknown rather than as an explicit zero.
    let reasoningKnown: Bool
    /// Something without a marker of its own happened between the previous request and this one: tools, waits,
    /// goal turns or unknown events. Human turns and compactions are marked on the main chart instead.
    let hasOtherActivity: Bool

    init(step: ContextAnatomyStep) {
        let input = Double(max(0, step.newInputTokens ?? step.contextTokens))
        let output = Double(max(0, step.outputTokens ?? 0))
        let total = input + output
        inputKnown = step.newInputTokens != nil
        outputKnown = step.outputTokens != nil
        reasoningKnown = !(step.reasoningOutputTokens == nil && output > 0)
        let activity = step.activityBefore
        hasOtherActivity = activity.tools + activity.waits + activity.goalTurns + activity.other > 0
        guard total > 0 else {
            inputFraction = 0
            outputFraction = 0
            reasoningFraction = 0
            return
        }
        inputFraction = input / total
        outputFraction = output / total
        let reasoning = min(Double(max(0, step.reasoningOutputTokens ?? 0)), output)
        reasoningFraction = reasoning / total
    }
}

/// One zone band of the context-size chart, in fractions of the anatomy's basis (window or session peak).
struct ContextZoneBand: Equatable, Identifiable {
    let zone: ContextFillZone
    let lowerFraction: Double
    let upperFraction: Double

    var id: ContextFillZone { zone }

    /// Mirrors `ContextAnatomyBuilder.zone(forFraction:)`: 0.5, 0.75 and 0.9 are the zone edges.
    static let all: [Self] = [
        Self(zone: .low, lowerFraction: 0, upperFraction: 0.5),
        Self(zone: .moderate, lowerFraction: 0.5, upperFraction: 0.75),
        Self(zone: .high, lowerFraction: 0.75, upperFraction: 0.9),
        Self(zone: .critical, lowerFraction: 0.9, upperFraction: 1)
    ]
}
