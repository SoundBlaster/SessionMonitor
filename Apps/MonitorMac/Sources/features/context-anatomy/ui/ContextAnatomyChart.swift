import Charts
import MonitorCore
import SwiftUI

/// Main stair-step chart plus a lane strip below it. Both share one x domain; the lane is padded by the
/// main chart's measured plot insets so every lane column sits directly under its request. The hover
/// snapshot floats over the plot as an overlay, so it never takes part in layout.
struct ContextAnatomyChart: View {
    let anatomy: ContextAnatomy
    let timeZone: TimeZone
    let palette: UsageChartPalette

    @State private var selectedX: Double?
    @State private var plotInsets = ContextAnatomyPlotInsets.zero

    private var stepCount: Int { anatomy.steps.count }
    private var selectedIndex: Int? {
        selectedX.flatMap { ContextAnatomyPresentation.stepIndex(forX: $0, stepCount: stepCount) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("relative to session peak: bands at 50%, 75% and 90%")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            sizeChart
            ContextAnatomyLane(steps: anatomy.steps, selectedIndex: selectedIndex, palette: palette)
                .padding(.leading, plotInsets.leading)
                .padding(.trailing, plotInsets.trailing)
        }
    }

    private var sizeChart: some View {
        Chart {
            zoneBands
            ForEach(anatomy.steps) { step in
                AreaMark(x: .value("Request", Double(step.index)),
                         y: .value("Context tokens", Double(step.contextTokens)))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(palette.accent.opacity(0.12))
                LineMark(x: .value("Request", Double(step.index)),
                         y: .value("Context tokens", Double(step.contextTokens)))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(palette.accent)
                    .accessibilityLabel("Request \(step.index)")
                    .accessibilityValue("Context \(ContextAnatomyPresentation.compactTokens(step.contextTokens))")
            }
            ForEach(anatomy.steps) { step in
                eventMarks(step)
            }
            if let index = selectedIndex {
                RuleMark(x: .value("Inspected request", Double(index)))
                    .foregroundStyle(palette.average.opacity(0.5))
            }
        }
        .chartXScale(domain: ContextAnatomyPresentation.xDomain(stepCount: stepCount))
        .chartYScale(domain: ContextAnatomyPresentation.yDomain(peak: anatomy.peakContextTokens))
        .chartXSelection(value: $selectedX)
        .chartXAxis {
            AxisMarks(values: ContextAnatomyPresentation.xTicks(stepCount: stepCount).map(Double.init)) { value in
                AxisGridLine().foregroundStyle(palette.grid)
                AxisTick()
                AxisValueLabel {
                    if let position = value.as(Double.self) { Text("\(Int(position))") }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(palette.grid)
                AxisTick()
                AxisValueLabel {
                    if let tokens = value.as(Double.self) {
                        Text(ContextAnatomyPresentation.compactTokens(Int64(tokens)))
                    }
                }
            }
        }
        .chartXAxisLabel("request", alignment: .center)
        .chartYAxisLabel("tokens", position: .leading)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                let insets = ContextAnatomyPlotInsets(proxy: proxy, geometry: geometry)
                ZStack(alignment: .topLeading) {
                    Color.clear.onChange(of: insets, initial: true) { plotInsets = $1 }
                    snapshotCard(proxy: proxy, geometry: geometry)
                }
                .allowsHitTesting(false)
            }
        }
        .frame(height: 220)
        .accessibilityLabel(ContextAnatomyPresentation.accessibilitySummary(anatomy))
        .accessibilityIdentifier("contextAnatomy.chart")
    }

    /// Floating card beside the inspected request's rule, near the top of the plot. Hit testing stays off
    /// (set by the overlay) so the card never steals the pointer that drives the selection.
    @ViewBuilder
    private func snapshotCard(proxy: ChartProxy, geometry: GeometryProxy) -> some View {
        if let index = selectedIndex, anatomy.steps.indices.contains(index - 1),
           let plotAnchor = proxy.plotFrame, let position = proxy.position(forX: Double(index)) {
            let plot = geometry[plotAnchor]
            let placement = ContextAnatomyPresentation.snapshotCardPlacement(
                anchorX: Double(position), plotWidth: Double(plot.width))
            let gap = CGFloat(ContextAnatomyPresentation.snapshotCardGap)
            let ruleX = plot.minX + position
            let lines = ContextAnatomyPresentation.snapshotLines(
                for: anatomy.steps[index - 1], in: anatomy, timeZone: timeZone)
            ContextAnatomySnapshotCard(lines: lines)
                .frame(width: CGFloat(placement.width))
                .fixedSize(horizontal: false, vertical: true)
                .alignmentGuide(.leading) { dimensions in
                    placement.side == .right ? -(ruleX + gap) : dimensions.width - (ruleX - gap)
                }
                .alignmentGuide(.top) { _ in -(plot.minY + gap) }
        }
    }

    @ChartContentBuilder
    private var zoneBands: some ChartContent {
        let domain = ContextAnatomyPresentation.xDomain(stepCount: stepCount)
        let peak = Double(max(1, anatomy.peakContextTokens))
        ForEach(ContextZoneBand.all) { band in
            RectangleMark(xStart: .value("From", domain.lowerBound), xEnd: .value("To", domain.upperBound),
                          yStart: .value("Band start", band.lowerFraction * peak),
                          yEnd: .value("Band end", band.upperFraction * peak))
                .foregroundStyle(palette.color(for: band.zone))
        }
    }

    @ChartContentBuilder
    private func eventMarks(_ step: ContextAnatomyStep) -> some ChartContent {
        if step.activityBefore.compactions > 0 {
            RuleMark(x: .value("Compaction", Double(step.index)))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(palette.color(for: .compaction).opacity(0.6))
            PointMark(x: .value("Request", Double(step.index)),
                      y: .value("Context tokens", Double(step.contextTokens)))
                .symbol(.diamond)
                .symbolSize(70)
                .foregroundStyle(palette.color(for: .compaction))
        }
        if step.activityBefore.humanTurns > 0 {
            PointMark(x: .value("Request", Double(step.index)),
                      y: .value("Context tokens", Double(step.contextTokens)))
                .symbol(.circle)
                .symbolSize(40)
                .foregroundStyle(palette.color(for: .humanTurn))
        }
    }
}

/// Horizontal distance between the chart view edges and its plot area.
struct ContextAnatomyPlotInsets: Equatable {
    var leading: CGFloat
    var trailing: CGFloat

    static let zero = Self(leading: 0, trailing: 0)

    init(leading: CGFloat, trailing: CGFloat) {
        self.leading = leading
        self.trailing = trailing
    }

    init(proxy: ChartProxy, geometry: GeometryProxy) {
        guard let anchor = proxy.plotFrame else {
            self = .zero
            return
        }
        let frame = geometry[anchor]
        self.init(leading: max(0, frame.minX), trailing: max(0, geometry.size.width - frame.maxX))
    }
}
