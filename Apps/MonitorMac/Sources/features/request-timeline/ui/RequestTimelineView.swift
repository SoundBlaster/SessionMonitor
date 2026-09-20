import Charts
import MonitorCore
import SwiftUI

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
                    rangeControls()
                    TimelineViewportControls(model: model, axis: axis)
                    timelineChart(timeline, axis: axis)
                    eventLegend(timeline, axis: axis)
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
        GeometryReader { geometry in
            RequestTimelinePlot(points: timeline.points, axis: axis,
                                timeZone: model.displayTimeZone, width: geometry.size.width)
        }
        .frame(height: RequestTimelineChartLayout.chartHeight + 60)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(RequestTimelineChartLayout.accessibilityLabel)
        .accessibilityValue(model.rangeDescription)
        .accessibilityHint(
            "The chart uses absolute event timestamps. Use Axis range to fit the data, "
                + "show the last events, or show the full query."
        )
        .accessibilityIdentifier("requestTimeline.chart")
    }

    private func eventLegend(_ timeline: RequestTimeline, axis: RequestTimelineAxis) -> some View {
        let events = timeline.points.filter {
            $0.kind != .usageRequest && axis.visibleDomain.contains($0.timestamp)
        }
        let kinds = TimelineEventKind.allCases.filter { kind in events.contains { $0.kind == kind } }
        return VStack(alignment: .leading, spacing: 6) {
            if !events.isEmpty {
                Text("Grouped events on baseline · counts in the visible range")
                    .font(.caption2).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading) {
                    ForEach(kinds, id: \.self) { kind in
                        Label("\(kind.label) · \(events.filter { $0.kind == kind }.count)", systemImage: "circle.fill")
                            .font(.caption2)
                            .foregroundStyle(kind.color)
                    }
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
                            Circle().fill(point.kind.color).frame(width: 7, height: 7)
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

}
