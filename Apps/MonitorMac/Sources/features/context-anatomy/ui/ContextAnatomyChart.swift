import Charts
import MonitorCore
import SwiftUI

/// Main stair-step chart plus a lane strip below it. Both share one x domain — the visible window (SM-722),
/// capped by data density so long sessions are never drawn all at once — and the lane is padded by the main
/// chart's measured plot insets so every lane column sits directly under its request. The hover snapshot
/// floats over the plot as an overlay, so it never takes part in layout.
struct ContextAnatomyChart: View {
    let anatomy: ContextAnatomy
    let timeZone: TimeZone
    let palette: UsageChartPalette

    @State private var inspection: ContextAnatomyInspection
    @State private var plotInsets = ContextAnatomyPlotInsets.zero
    @State private var plotWidth = 0.0
    @State private var storedViewport: ContextAnatomyViewport?

    init(anatomy: ContextAnatomy, timeZone: TimeZone, palette: UsageChartPalette,
         inspection: ContextAnatomyInspection = ContextAnatomyInspection()) {
        self.anatomy = anatomy
        self.timeZone = timeZone
        self.palette = palette
        _inspection = State(initialValue: inspection)
    }

    private var stepCount: Int { anatomy.steps.count }
    private var viewport: ContextAnatomyViewport {
        storedViewport ?? .initial(stepCount: stepCount, plotWidth: plotWidth)
    }
    private var domain: ClosedRange<Double> { viewport.domain }
    private var visibleSteps: [ContextAnatomyStep] {
        guard let range = viewport.visibleIndices(stepCount: stepCount) else { return [] }
        return Array(anatomy.steps[(range.lowerBound - 1)...(range.upperBound - 1)])
    }

    var body: some View {
        let steps = visibleSteps
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(ContextAnatomyPresentation.windowLabel(for: domain, stepCount: stepCount) ?? " ")
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Text(ContextAnatomyPresentation.columnCaption(for: anatomy.basis))
                    .fixedSize()
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            sizeChart(steps)
                .focusable()
                .onKeyPress(.leftArrow) { step(by: -1) }
                .onKeyPress(.rightArrow) { step(by: 1) }
                .overlay(alignment: .topLeading) {
                    ContextAnatomyInspectionAccessibility(anatomy: anatomy, timeZone: timeZone,
                                                         inspection: inspection, onStep: { step(by: $0) })
                }
            ContextAnatomyLane(steps: steps, domain: domain, inspection: inspection, palette: palette)
                .padding(.leading, plotInsets.leading)
                .padding(.trailing, plotInsets.trailing)
            if Double(stepCount) > ContextAnatomyViewport.minVisibleRequests {
                ContextAnatomyOverviewSlider(anatomy: anatomy, domain: domain, palette: palette) { position in
                    storedViewport = viewport.centered(on: position, stepCount: stepCount)
                }
                .padding(.leading, plotInsets.leading)
                .padding(.trailing, plotInsets.trailing)
                .padding(.top, 4)
            }
        }
        .onChange(of: stepCount) { oldCount, newCount in
            storedViewport = storedViewport?.following(growthFrom: oldCount, to: newCount, plotWidth: plotWidth)
            inspection.reconcile(stepCount: newCount)
        }
    }

    private func updatePlotWidth(_ width: Double) {
        guard width.isFinite, width > 0, width != plotWidth else { return }
        let previous = storedViewport ?? .initial(stepCount: stepCount, plotWidth: width)
        plotWidth = width
        storedViewport = previous.clamped(stepCount: stepCount, plotWidth: width)
    }

    private func zoom(by factor: Double, anchor: Double) {
        storedViewport = viewport.magnified(by: factor, anchor: anchor, stepCount: stepCount, plotWidth: plotWidth)
    }

    /// Returns whether the window moved, so an edge hands the scroll back to the page.
    private func pan(by translation: Double) -> Bool {
        let moved = viewport.panned(byPoints: translation, stepCount: stepCount, plotWidth: plotWidth)
        guard moved != viewport else { return false }
        storedViewport = moved
        return true
    }

    @discardableResult
    private func step(by delta: Int) -> KeyPress.Result {
        guard let index = inspection.move(by: delta, stepCount: stepCount) else { return .ignored }
        let revealed = viewport.revealing(index, stepCount: stepCount, plotWidth: plotWidth)
        if revealed != viewport { storedViewport = revealed }
        return .handled
    }

    private func sizeChart(_ steps: [ContextAnatomyStep]) -> some View {
        Chart {
            zoneColumns(steps)
            ForEach(ContextAnatomyPresentation.linePoints(for: steps, stepCount: stepCount)) { point in
                LineMark(x: .value("Request", point.x), y: .value("Context tokens", point.y))
                    // Centred steps span each request's column, so the line runs exactly along the column tops.
                    .interpolationMethod(.stepCenter)
                    .foregroundStyle(palette.accent)
                    .accessibilityHidden(point.stepIndex == nil)
                    .accessibilityLabel(point.stepIndex.map { "Request \($0)" } ?? "")
                    .accessibilityValue("Context \(ContextAnatomyPresentation.compactTokens(Int64(point.y)))")
            }
            ForEach(steps) { step in
                eventMarks(step)
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: ContextAnatomyPresentation.yDomain(peak: anatomy.peakContextTokens))
        .chartPlotStyle { $0.clipped() }
        .chartXAxis { requestAxis }
        .chartYAxis { tokenAxis }
        .chartXAxisLabel("request", alignment: .center)
        .chartYAxisLabel("tokens", position: .leading)
        .chartOverlay { proxy in plotOverlay(proxy: proxy) }
        .frame(height: 220)
        .accessibilityLabel(ContextAnatomyPresentation.accessibilitySummary(anatomy))
        .accessibilityIdentifier("contextAnatomy.chart")
    }

    @AxisContentBuilder private var requestAxis: some AxisContent {
        let ticks = ContextAnatomyPresentation.xTicks(in: domain, stepCount: stepCount).map(Double.init)
        AxisMarks(values: ticks) { value in
            AxisGridLine().foregroundStyle(palette.grid)
            AxisTick()
            AxisValueLabel {
                if let position = value.as(Double.self) { Text("\(Int(position))") }
            }
        }
    }

    @AxisContentBuilder private var tokenAxis: some AxisContent {
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

    /// Measures the plot, takes hover/zoom/pan over the plot area, and floats the snapshot card.
    private func plotOverlay(proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            let insets = ContextAnatomyPlotInsets(proxy: proxy, geometry: geometry)
            let plot = proxy.plotFrame.map { geometry[$0] } ?? .zero
            ZStack(alignment: .topLeading) {
                Color.clear
                    .onChange(of: insets, initial: true) { plotInsets = $1 }
                    .onChange(of: plot.width, initial: true) { updatePlotWidth(Double($1)) }
                    .allowsHitTesting(false)
                ContextAnatomyInspectionOverlay(
                    anatomy: anatomy, timeZone: timeZone, palette: palette,
                    inspection: inspection, proxy: proxy, plot: plot,
                    onZoom: { zoom(by: $0, anchor: $1) },
                    onPan: { pan(by: $0) }
                )
            }
        }
    }

    /// SM-725: one column per request, coloured by its context zone; the step line masks them from above.
    @ChartContentBuilder
    private func zoneColumns(_ steps: [ContextAnatomyStep]) -> some ChartContent {
        ForEach(steps) { step in
            let column = ContextAnatomyPresentation.zoneColumn(for: step)
            RectangleMark(xStart: .value("From", column.xStart), xEnd: .value("To", column.xEnd),
                          yStart: .value("Base", 0.0), yEnd: .value("Context tokens", column.top))
                .foregroundStyle(palette.color(for: column.zone))
                .accessibilityHidden(true)
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
