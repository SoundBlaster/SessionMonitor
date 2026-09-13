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
                timelineChart(timeline)
                evidenceList(timeline)
            } else {
                ContentUnavailableView("No timeline evidence", systemImage: "chart.xyaxis.line",
                                       description: Text("No events are available in the selected period."))
                    .frame(maxWidth: .infinity, minHeight: 150)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Request timeline for \(query.timeZoneIdentifier)")
    }

    @ViewBuilder
    private func timelineChart(_ timeline: RequestTimeline) -> some View {
        let chartWidth = max(480, CGFloat(timeline.points.count) * 28)
        ScrollView(.horizontal, showsIndicators: timeline.points.count > 16) {
            Chart {
                ForEach(timeline.points) { point in
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
            .chartForegroundStyleScale([
                "Cached input": Color.accentColor,
                "Uncached input": Color.secondary
            ])
            .chartLegend(position: .bottom, alignment: .leading)
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(width: chartWidth, height: 250)
            .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Cached and uncached input over time")
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
                            Text(point.timestamp, format: .dateTime.hour().minute().second())
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
