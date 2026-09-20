import Charts
import MonitorCore
import SwiftUI

struct RequestTimelinePlot: View {
    let points: [RequestTimelinePoint]
    let axis: RequestTimelineAxis
    let timeZone: TimeZone
    let width: CGFloat

    var body: some View {
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
                BarMark(x: .value("Time", point.timestamp),
                        yStart: .value("Tokens", 0), yEnd: .value("Tokens", cached),
                        width: .fixed(RequestTimelineChartLayout.barWidth))
                    .foregroundStyle(by: .value("Evidence", "Cached input"))

            }
            if let uncached = point.uncachedInputTokens {
                BarMark(x: .value("Time", point.timestamp),
                        yStart: .value("Tokens", Double(point.cachedInputTokens ?? 0)),
                        yEnd: .value("Tokens", Double(point.cachedInputTokens ?? 0) + Double(uncached)),
                        width: .fixed(RequestTimelineChartLayout.barWidth))
                    .foregroundStyle(by: .value("Evidence", "Uncached input"))

            }
            if point.kind != .usageRequest {
                PointMark(x: .value("Time", point.timestamp), y: .value("Tokens", 0))
                    .symbol(.circle)
                    .foregroundStyle(point.kind.color)
                    .symbolSize(RequestTimelineChartLayout.eventSymbolSize)
                    .accessibilityLabel(point.kind.label)
                    .accessibilityValue(point.timestamp.formatted(axisDateFormat(for: 0)))
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
    var color: Color {
        switch self {
        case .usageRequest: .accentColor
        case .humanTurn: .green
        case .goalTurn: .indigo
        case .compaction: .orange
        case .tool: .purple
        case .wait: .teal
        case .unknown: .gray
        }
    }

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
