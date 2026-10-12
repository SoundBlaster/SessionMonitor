import Foundation
import MonitorCore

/// SM-722: the whole-session overview slider under the context-anatomy chart. Pure rules: the downsampled
/// preview and the mapping between the request axis and overview points.
enum ContextAnatomyOverview {
    /// Consecutive requests drawn as one overview column.
    struct Bucket: Equatable {
        let firstIndex: Int
        let lastIndex: Int
        /// The largest context in the bucket, so peaks and the drops after compactions stay visible.
        let peakContext: Int64
        /// The zone of that largest request.
        let zone: ContextFillZone
    }

    /// At most `count` buckets of equal request runs covering every step exactly once.
    static func buckets(of steps: [ContextAnatomyStep], count: Int) -> [Bucket] {
        guard !steps.isEmpty, count > 0 else { return [] }
        let size = Int((Double(steps.count) / Double(count)).rounded(.up))
        return Swift.stride(from: 0, to: steps.count, by: size).compactMap { start in
            let run = steps[start..<min(steps.count, start + size)]
            guard let peak = run.max(by: { $0.contextTokens < $1.contextTokens }),
                  let first = run.first, let last = run.last else { return nil }
            return Bucket(firstIndex: first.index, lastIndex: last.index,
                          peakContext: peak.contextTokens, zone: peak.zone)
        }
    }

    /// Where the visible window sits inside an overview `width` points wide.
    static func windowFrame(for domain: ClosedRange<Double>, stepCount: Int, width: Double) -> ClosedRange<Double> {
        guard stepCount > 0, width > 0 else { return 0...0 }
        let scale = width / Double(stepCount)
        let start = min(max((domain.lowerBound - 0.5) * scale, 0), width)
        let end = min(max((domain.upperBound - 0.5) * scale, start), width)
        return start...end
    }

    /// VoiceOver adjust on the overview: the window centre one window width earlier (-1) or later (+1).
    /// The viewport clamps the result to the session.
    static func pagedCenter(for domain: ClosedRange<Double>, by pages: Int) -> Double {
        let span = domain.upperBound - domain.lowerBound
        return (domain.lowerBound + domain.upperBound) / 2 + Double(pages) * span
    }

    /// The request-axis position under an overview x coordinate, clamped to the session.
    static func axisPosition(atX pointX: Double, stepCount: Int, width: Double) -> Double {
        guard stepCount > 0, width > 0, pointX.isFinite else { return 0.5 }
        return 0.5 + min(max(pointX, 0), width) / width * Double(stepCount)
    }
}
