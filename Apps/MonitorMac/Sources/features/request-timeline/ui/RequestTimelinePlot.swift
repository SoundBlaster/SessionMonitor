import Charts
import MonitorCore
import SwiftUI

struct RequestTimelinePlot: View {
    let points: [RequestTimelinePoint]
    let axis: RequestTimelineAxis
    let timeZone: TimeZone
    let width: CGFloat
    var palette: UsageChartPalette = .system

    var body: some View {
        let aggregation = TimelineAggregation(points: points, domain: axis.visibleDomain, width: width)
        let yScale = TimelineYAxisScale(points: points, navigationDomain: axis.navigationDomain,
                                        width: Double(width))
        VStack(alignment: .leading, spacing: 8) {
            Text(aggregation.description)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("requestTimeline.aggregation")
            Chart { timelineMarks(aggregation.buckets) }
                .chartXScale(domain: axis.visibleDomain.start...axis.visibleDomain.end)
                .chartForegroundStyleScale([
                    "Cached input": palette.accent,
                    "Uncached input": palette.neutral
                ])
                .chartLegend(position: .bottom, alignment: .leading)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine().foregroundStyle(palette.grid)
                        AxisTick()
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(date.formatted(axisDateFormat(for: axis.visibleDomain.duration)))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine().foregroundStyle(palette.grid)
                        AxisTick()
                        AxisValueLabel().foregroundStyle(palette.neutral)
                    }
                }
                .chartYScale(domain: yScale.domain,
                             range: .plotDimension(padding: RequestTimelineChartLayout.yAxisTopInset))
                .frame(height: RequestTimelineChartLayout.chartHeight)
        }
        .frame(width: max(1, width - 8), alignment: .leading)
        .padding(.horizontal, 4)
    }

    @ChartContentBuilder
    private func timelineMarks(_ buckets: [TimelineBucket]) -> some ChartContent {
        ForEach(buckets) { bucket in
            if bucket.knownRequestCount > 0 {
                BarMark(x: .value("Time", bucket.timestamp),
                        yStart: .value("Tokens", 0), yEnd: .value("Tokens", bucket.cached),
                        width: .fixed(RequestTimelineChartLayout.barWidth))
                    .foregroundStyle(by: .value("Evidence", "Cached input"))
                    .accessibilityLabel("\(bucket.knownRequestCount) known requests, cached token sum")
                    .accessibilityValue(bucket.cached.formatted())
                BarMark(x: .value("Time", bucket.timestamp),
                        yStart: .value("Tokens", bucket.cached),
                        yEnd: .value("Tokens", bucket.cached + bucket.uncached),
                        width: .fixed(RequestTimelineChartLayout.barWidth))
                    .foregroundStyle(by: .value("Evidence", "Uncached input"))
                    .accessibilityLabel("Uncached token sum")
                    .accessibilityValue(bucket.uncached.formatted())
            }
            if bucket.eventCount > 0 || bucket.unknownRequestCount > 0 {
                PointMark(x: .value("Time", bucket.timestamp), y: .value("Tokens", 0))
                    .symbol(.diamond)
                    .foregroundStyle(bucket.unknownRequestCount > 0 ? palette.warning : palette.neutral)
                    .symbolSize(RequestTimelineChartLayout.eventSymbolSize)
                    .accessibilityLabel("\(bucket.eventCount) events, "
                        + "\(bucket.unknownRequestCount) unavailable requests")
                    .accessibilityValue(timelineAccessibilityDateLabel(
                        bucket.timestamp,
                        duration: axis.visibleDomain.duration,
                        timeZone: timeZone
                    ))
            }
        }
    }

    private func axisDateFormat(for duration: TimeInterval) -> Date.FormatStyle {
        var format = Date.FormatStyle(
            date: duration >= 24 * 60 * 60 ? .abbreviated : .omitted,
            time: duration < 5 * 60 ? .standard : .shortened
        )
        format.timeZone = timeZone
        return format
    }

}

extension TimelineEventKind {
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
