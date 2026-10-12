import Foundation

/// SM-722: the visible request window of the context-anatomy chart, in request-axis units. The full axis is
/// `0.5...(N + 0.5)`, one unit per request. Data density is capped: every request gets at least
/// `minPointsPerRequest` points of plot width, so multi-day sessions are never drawn all at once.
struct ContextAnatomyViewport: Equatable {
    static let minPointsPerRequest = 2.0
    static let minVisibleRequests = 10.0
    /// Mouse-wheel line deltas are scaled to trackpad points before they become a zoom factor.
    static let wheelStep = 12.0
    /// Zoom sensitivity per point of ⌘-scroll.
    static let scrollZoomRate = 0.01

    private(set) var lowerBound: Double
    private(set) var span: Double

    var domain: ClosedRange<Double> { lowerBound...(lowerBound + span) }

    /// Most requests that fit at the density cap; never below the minimum window.
    static func maxSpan(plotWidth: Double) -> Double {
        guard plotWidth.isFinite, plotWidth > 0 else { return minVisibleRequests }
        return max(minVisibleRequests, (plotWidth / minPointsPerRequest).rounded(.down))
    }

    /// The whole session when it fits the cap, otherwise the latest requests that do.
    static func initial(stepCount: Int, plotWidth: Double) -> Self {
        guard stepCount > 0 else { return Self(lowerBound: 0.5, span: 1) }
        let span = min(Double(stepCount), maxSpan(plotWidth: plotWidth))
        return Self(lowerBound: Double(stepCount) + 0.5 - span, span: span)
    }

    /// Keeps the window inside the session and the density cap after the plot or the session changes.
    /// A window that shrinks keeps its right edge, so the latest requests stay in view.
    func clamped(stepCount: Int, plotWidth: Double) -> Self {
        guard stepCount > 0 else { return Self(lowerBound: 0.5, span: 1) }
        let limits = Self.spanLimits(stepCount: stepCount, plotWidth: plotWidth)
        let newSpan = min(max(span, limits.lowerBound), limits.upperBound)
        return Self(lowerBound: lowerBound + span - newSpan, span: newSpan).bounded(stepCount: stepCount)
    }

    /// Zooms by `factor` (> 1 shows fewer requests) keeping the request at `anchor` (a fraction of the plot
    /// width) under the pointer. Invalid input leaves the window unchanged.
    func magnified(by factor: Double, anchor: Double, stepCount: Int, plotWidth: Double) -> Self {
        guard factor.isFinite, factor > 0, anchor.isFinite, stepCount > 0 else { return self }
        let fraction = min(max(anchor, 0), 1)
        let limits = Self.spanLimits(stepCount: stepCount, plotWidth: plotWidth)
        let newSpan = min(max(span / factor, limits.lowerBound), limits.upperBound)
        let anchorX = lowerBound + fraction * span
        return Self(lowerBound: anchorX - fraction * newSpan, span: newSpan).bounded(stepCount: stepCount)
    }

    /// Positive translation moves the plotted data right, revealing earlier requests.
    func panned(byPoints translation: Double, stepCount: Int, plotWidth: Double) -> Self {
        guard translation.isFinite, plotWidth.isFinite, plotWidth > 0, stepCount > 0 else { return self }
        return Self(lowerBound: lowerBound - translation / plotWidth * span, span: span).bounded(stepCount: stepCount)
    }

    /// The same window centred on an axis position, as when the overview is clicked or its frame dragged.
    func centered(on position: Double, stepCount: Int) -> Self {
        guard position.isFinite, stepCount > 0 else { return self }
        return Self(lowerBound: position - span / 2, span: span).bounded(stepCount: stepCount)
    }

    /// The smallest shift that brings request `index` fully into view.
    func revealing(_ index: Int, stepCount: Int, plotWidth: Double) -> Self {
        guard (1...max(1, stepCount)).contains(index), stepCount > 0 else { return self }
        let start = Double(index) - 0.5
        let end = Double(index) + 0.5
        if start < lowerBound { return Self(lowerBound: start, span: span).bounded(stepCount: stepCount) }
        if end > lowerBound + span { return Self(lowerBound: end - span, span: span).bounded(stepCount: stepCount) }
        return self
    }

    /// Live sessions: a window on the latest requests follows new ones, a whole session stays whole while it
    /// fits the cap, a window in the past stays put, and a shorter session (another one) starts over.
    func following(growthFrom oldCount: Int, to newCount: Int, plotWidth: Double) -> Self {
        guard newCount > 0, oldCount > 0, newCount >= oldCount else {
            return Self.initial(stepCount: newCount, plotWidth: plotWidth)
        }
        if span >= Double(oldCount) { return Self.initial(stepCount: newCount, plotWidth: plotWidth) }
        let wasAtEnd = abs(lowerBound + span - (Double(oldCount) + 0.5)) < 1e-9
        guard wasAtEnd else { return clamped(stepCount: newCount, plotWidth: plotWidth) }
        return Self(lowerBound: lowerBound + Double(newCount - oldCount), span: span)
            .clamped(stepCount: newCount, plotWidth: plotWidth)
    }

    /// Requests to draw: the window plus one neighbour on each side, so step lines reach both edges.
    func visibleIndices(stepCount: Int) -> ClosedRange<Int>? {
        guard stepCount > 0 else { return nil }
        let first = max(1, Int(lowerBound.rounded(.down)))
        let last = min(stepCount, Int((lowerBound + span).rounded(.up)))
        return first <= last ? first...last : nil
    }

    /// ⌘-scroll: a positive delta (scrolling up) zooms in. Wheel line deltas count as `wheelStep` points.
    static func zoomFactor(forScrollDelta delta: Double, precise: Bool) -> Double {
        guard delta.isFinite else { return 1 }
        return exp((precise ? delta : delta * wheelStep) * scrollZoomRate)
    }

    private static func spanLimits(stepCount: Int, plotWidth: Double) -> ClosedRange<Double> {
        let count = Double(stepCount)
        let upper = min(count, maxSpan(plotWidth: plotWidth))
        return min(minVisibleRequests, upper)...upper
    }

    private func bounded(stepCount: Int) -> Self {
        let maxLower = Double(stepCount) + 0.5 - span
        return Self(lowerBound: min(max(lowerBound, 0.5), maxLower), span: span)
    }
}
