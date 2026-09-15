import Charts
import MonitorCore
import SwiftUI

enum RequestTimelineChartLayout {
    static let chartHeight: CGFloat = 250
    static let yAxisTopInset: CGFloat = 16
    static let maxChartPoints = 256
    static let accessibilityLabel = "Cached and uncached input over time"

    /// Keep the evidence list complete, but cap the number of marks that Charts lays out.
    /// This is a presentation-only projection; it never changes the loaded timeline.
    static func chartPoints(from points: [RequestTimelinePoint]) -> [RequestTimelinePoint] {
        guard points.count > maxChartPoints else { return points }

        let lastIndex = points.count - 1
        var selectedIndices: Set<Int> = [0, lastIndex]
        selectedIndices.formUnion(points.indices.filter { points[$0].kind != .usageRequest })

        if selectedIndices.count >= maxChartPoints {
            let semanticIndices = selectedIndices.sorted()
            let step = Double(semanticIndices.count - 1) / Double(maxChartPoints - 1)
            return (0..<maxChartPoints).map { offset in
                semanticIndices[Int((Double(offset) * step).rounded())]
            }.map { points[$0] }
        }

        let candidates = points.indices.filter { !selectedIndices.contains($0) }
        let slots = maxChartPoints - selectedIndices.count
        for slot in 0..<slots {
            let offset = min(
                candidates.count - 1,
                Int(Double(slot) * Double(candidates.count) / Double(slots))
            )
            selectedIndices.insert(candidates[offset])
        }
        return selectedIndices.sorted().map { points[$0] }
    }
}

struct RequestTimelineView: View {
    let model: RequestTimelineModel
    let query: UsageQuery

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Request timeline", systemImage: "chart.xyaxis.line")
                .font(.title2.bold())
            Text("Presentation evidence for this session and the selected absolute period. "
                 + "It does not change canonical accounting.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if model.isLoading && model.timeline == nil {
                ProgressView("Loading evidence…")
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            } else if let timeline = model.timeline, !timeline.isEmpty {
                if let axis = model.axis {
                    if timeline.points.count > RequestTimelineChartLayout.maxChartPoints {
                        Text("Dense timeline: chart shows representative events; "
                             + "the complete evidence list remains below.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    rangeControls()
                    timelineChart(timeline, axis: axis)
                    evidenceList(timeline)
                } else {
                    emptyState
                }
            } else {
                emptyState
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Request timeline for \(query.timeZoneIdentifier)")
    }

    private var emptyState: some View {
        ContentUnavailableView("No timeline evidence", systemImage: "chart.xyaxis.line",
                               description: Text("No events are available in the selected period."))
            .frame(maxWidth: .infinity, minHeight: 150)
    }

    private func rangeControls() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Axis range")
                    .font(.headline)
                Spacer(minLength: 8)
                ViewThatFits(in: .horizontal) {
                    rangePicker
                    rangePickerMenu
                }
            }
            Text(model.rangeDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Current timeline range")
                .accessibilityValue(model.rangeDescription)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("requestTimeline.rangeControls")
    }

    private var rangePicker: some View {
        Picker("Timeline range", selection: Binding(
            get: { model.rangeMode },
            set: { model.setRangeMode($0) }
        )) {
            ForEach(RequestTimelineRangeMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("requestTimeline.rangeMode")
    }

    private var rangePickerMenu: some View {
        Picker("Timeline range", selection: Binding(
            get: { model.rangeMode },
            set: { model.setRangeMode($0) }
        )) {
            ForEach(RequestTimelineRangeMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("requestTimeline.rangeMode")
    }

    private func timelineChart(_ timeline: RequestTimeline, axis: RequestTimelineAxis) -> some View {
        let chartPoints = RequestTimelineChartLayout.chartPoints(from: timeline.points)
        return GeometryReader { geometry in
            let chartWidth = max(CGFloat(axis.preferredChartWidth), geometry.size.width)
            ScrollView(.horizontal, showsIndicators: chartWidth > geometry.size.width) {
                timelineChartContent(points: chartPoints, axis: axis, width: chartWidth)
            }
            .frame(
                width: geometry.size.width,
                height: RequestTimelineChartLayout.chartHeight,
                alignment: .leading
            )
        }
        .frame(height: RequestTimelineChartLayout.chartHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(RequestTimelineChartLayout.accessibilityLabel)
        .accessibilityValue(model.rangeDescription)
        .accessibilityHint(
            "The chart uses absolute event timestamps. Use Axis range to fit the data, "
                + "show the last events, or show the full query."
        )
        .accessibilityIdentifier("requestTimeline.chart")
    }

    private func timelineChartContent(
        points: [RequestTimelinePoint], axis: RequestTimelineAxis, width: CGFloat
    ) -> some View {
        Chart { timelineMarks(points) }
            .chartXScale(domain: axis.visibleDomain.start...axis.visibleDomain.end)
            .chartForegroundStyleScale([
                "Cached input": Color.accentColor,
                "Uncached input": Color.secondary
            ])
            .chartLegend(position: .bottom, alignment: .leading)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date.formatted(axisDateFormat(for: axis.visibleDomain.duration)))
                        }
                    }
                }
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .chartYScale(range: .plotDimension(padding: RequestTimelineChartLayout.yAxisTopInset))
            .frame(width: width, height: RequestTimelineChartLayout.chartHeight)
            .padding(.horizontal, 4)
    }

    @ChartContentBuilder
    private func timelineMarks(_ points: [RequestTimelinePoint]) -> some ChartContent {
        ForEach(points) { point in
            if let cached = point.cachedInputTokens {
                BarMark(x: .value("Time", point.timestamp), y: .value("Tokens", cached))
                    .foregroundStyle(by: .value("Evidence", "Cached input"))
                    .position(by: .value("Evidence", "Cached input"))
            }
            if let uncached = point.uncachedInputTokens {
                BarMark(x: .value("Time", point.timestamp), y: .value("Tokens", uncached))
                    .foregroundStyle(by: .value("Evidence", "Uncached input"))
                    .position(by: .value("Evidence", "Uncached input"))
            }
            if point.kind != .usageRequest {
                PointMark(x: .value("Time", point.timestamp), y: .value("Tokens", 0))
                    .symbol(.circle)
                    .foregroundStyle(eventColor(point.kind))
                    .annotation(position: .top, alignment: .center) {
                        Text(point.kind.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
            }
        }
    }

    private func evidenceList(_ timeline: RequestTimeline) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Evidence")
                .font(.headline)
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 7) {
                    ForEach(timeline.points) { point in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(eventColor(point.kind)).frame(width: 7, height: 7)
                            Text(point.kind.label)
                                .font(.callout)
                            if let cached = point.cachedInputTokens, let uncached = point.uncachedInputTokens {
                                Text("\(cached.formatted()) cached · \(uncached.formatted()) uncached")
                                    .foregroundStyle(.secondary)
                            } else if point.kind == .usageRequest {
                                Text("Unavailable")
                                    .foregroundStyle(.orange)
                            } else if let evidence = point.evidence {
                                Text(evidence)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Text(point.timestamp.formatted(evidenceDateFormat(for: timeline)))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .frame(maxHeight: 260, alignment: .top)
        }
    }

    private func evidenceDateFormat(for timeline: RequestTimeline) -> Date.FormatStyle {
        let first = timeline.points.first?.timestamp ?? .distantPast
        let last = timeline.points.last?.timestamp ?? first
        let span = last.timeIntervalSince(first)
        var format = Date.FormatStyle(date: span >= 24 * 60 * 60 ? .abbreviated : .omitted, time: .standard)
        format.timeZone = model.displayTimeZone
        return format
    }

    private func axisDateFormat(for duration: TimeInterval) -> Date.FormatStyle {
        var format = Date.FormatStyle(
            date: duration >= 24 * 60 * 60 ? .abbreviated : .omitted,
            time: duration < 5 * 60 ? .standard : .shortened
        )
        format.timeZone = model.displayTimeZone
        return format
    }

    private func eventColor(_ kind: TimelineEventKind) -> Color {
        switch kind {
        case .usageRequest: .accentColor
        case .humanTurn: .green
        case .goalTurn: .indigo
        case .compaction: .orange
        case .tool: .purple
        case .wait: .teal
        case .unknown: .gray
        }
    }
}

private extension TimelineEventKind {
    var label: String {
        switch self {
        case .usageRequest: "Usage request"
        case .humanTurn: "Human turn"
        case .goalTurn: "Goal / continuation turn"
        case .compaction: "Compaction"
        case .tool: "Tool"
        case .wait: "Wait"
        case .unknown: "Unknown event"
        }
    }
}
