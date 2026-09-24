import MonitorCore
import NestedA11yIDs
import SwiftUI

struct RequestTimelineViewportView: View {
    let model: RequestTimelineModel
    let pointIndex: TimelinePointIndex
    let palette: UsageChartPalette

    var body: some View {
        if let axis = model.axis {
            VStack(alignment: .leading, spacing: 14) {
                rangeControls(axis: axis)
                TimelineViewportControls(model: model, axis: axis)
                timelineChart(axis: axis)
                TimelineEventLegend(pointIndex: pointIndex, domain: axis.visibleDomain, palette: palette)
            }
        }
    }

    private func rangeControls(axis: RequestTimelineAxis) -> some View {
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
            Text(axis.description(timeZone: model.displayTimeZone))
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Current timeline range")
                .accessibilityValue(axis.description(timeZone: model.displayTimeZone))
                .fixedSize(horizontal: false, vertical: true)
        }
        .nestedAccessibilityIdentifier("rangeControls")
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
        .accessibilityIdentifier("requestTimeline.rangeControls.rangeMode")
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
        .accessibilityIdentifier("requestTimeline.rangeControls.rangeMode")
    }

    private func timelineChart(axis: RequestTimelineAxis) -> some View {
        GeometryReader { geometry in
            if let scale = model.yAxisScale(for: axis, width: Double(geometry.size.width)) {
                RequestTimelinePlot(pointIndex: pointIndex, axis: axis, timeZone: model.displayTimeZone,
                                    width: geometry.size.width, palette: palette, yAxisScale: scale)
            }
        }
        .frame(height: RequestTimelineChartLayout.chartHeight + 60)
        .nestedAccessibilityIdentifier("chart")
        .accessibilityLabel(RequestTimelineChartLayout.accessibilityLabel)
        .accessibilityValue(axis.description(timeZone: model.displayTimeZone))
        .accessibilityHint(
            "The chart uses absolute event timestamps. Use Axis range to fit the data, "
                + "show the last events, or show the full query."
        )
    }
}

private struct TimelineEventLegend: View {
    let pointIndex: TimelinePointIndex
    let domain: DateInterval
    let palette: UsageChartPalette

    var body: some View {
        let eventCounts = pointIndex.eventCounts(in: domain)
        return VStack(alignment: .leading, spacing: 6) {
            if !eventCounts.isEmpty {
                Text("Grouped events on baseline · counts in the visible range")
                    .font(.caption2).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading) {
                    ForEach(eventCounts) { event in
                        Label("\(event.kind.label) · \(event.count)", systemImage: "circle.fill")
                            .font(.caption2)
                            .foregroundStyle(palette.color(for: event.kind))
                    }
                }
            }
        }
    }
}
