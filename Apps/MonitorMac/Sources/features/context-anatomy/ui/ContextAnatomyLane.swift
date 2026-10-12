import Charts
import MonitorCore
import SwiftUI

/// Per-request lane strip: each column splits into new input and output, with reasoning as a darker part
/// of the output segment and a left-edge tick when tools or waits happened before the request.
struct ContextAnatomyLane: View {
    /// Only the steps of the visible window (SM-722); the domain is the main chart's window.
    let steps: [ContextAnatomyStep]
    let domain: ClosedRange<Double>
    let selectedIndex: Int?
    let palette: UsageChartPalette

    private let columnInset = 0.1

    var body: some View {
        Chart {
            ForEach(steps) { step in
                columnMarks(step, lane: ContextLaneSegments(step: step))
            }
            if let index = selectedIndex {
                RectangleMark(xStart: .value("From", Double(index) - 0.5), xEnd: .value("To", Double(index) + 0.5),
                              yStart: .value("Low", 0.0), yEnd: .value("High", 1.0))
                    .foregroundStyle(palette.average.opacity(0.12))
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: 0.0...1.0)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartPlotStyle { $0.clipped() }
        .frame(height: 40)
        .accessibilityHidden(true)
    }

    @ChartContentBuilder
    private func columnMarks(_ step: ContextAnatomyStep, lane: ContextLaneSegments) -> some ChartContent {
        let start = Double(step.index) - 0.5 + columnInset
        let width = 1 - 2 * columnInset
        let inputEnd = start + width * lane.inputFraction
        let outputEnd = inputEnd + width * lane.outputFraction
        if lane.inputFraction > 0 {
            segment(from: start, to: inputEnd)
                .foregroundStyle(lane.inputKnown ? color(.newInput).opacity(0.75) : palette.neutral.opacity(0.4))
        }
        if lane.outputFraction > 0 {
            segment(from: inputEnd, to: outputEnd)
                .foregroundStyle(color(.output).opacity(0.5))
        }
        if lane.reasoningFraction > 0 {
            segment(from: inputEnd, to: inputEnd + width * lane.reasoningFraction)
                .foregroundStyle(color(.reasoning))
        }
        if lane.outputFraction > 0, !lane.reasoningKnown {
            // Thin neutral band at the bottom of the output segment: reasoning tokens are unknown.
            RectangleMark(xStart: .value("From", inputEnd), xEnd: .value("To", outputEnd),
                          yStart: .value("Low", 0.0), yEnd: .value("High", 0.25))
                .foregroundStyle(palette.neutral.opacity(0.5))
        }
        if lane.hasToolsOrWaits {
            segment(from: Double(step.index) - 0.5, to: start)
                .foregroundStyle(color(.toolsOrWaits))
        }
    }

    private func color(_ kind: ContextLaneSegments.Kind) -> Color { palette.color(for: kind.flow) }

    private func segment(from start: Double, to end: Double) -> some ChartContent {
        RectangleMark(xStart: .value("From", start), xEnd: .value("To", end),
                      yStart: .value("Low", 0.0), yEnd: .value("High", 1.0))
    }
}
