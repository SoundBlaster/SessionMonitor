import MonitorCore
import NestedA11yIDs
import SwiftUI

struct RequestTimelineView: View {
    let model: RequestTimelineModel
    let query: UsageQuery
    var palette: UsageChartPalette = .system

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
            } else if let timeline = model.timeline,
                      !timeline.isEmpty,
                      let pointIndex = model.pointIndex {
                RequestTimelineViewportView(model: model, pointIndex: pointIndex, palette: palette)
                TimelineEvidenceList(points: pointIndex.points,
                                     timeZone: model.displayTimeZone,
                                     palette: palette)
            } else {
                emptyState
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
        .a11yRoot("requestTimeline")
        .accessibilityLabel("Request timeline for \(query.timeZoneIdentifier)")
    }

    private var emptyState: some View {
        ContentUnavailableView("No timeline evidence", systemImage: "chart.xyaxis.line",
                               description: Text("No events are available in the selected period."))
            .frame(maxWidth: .infinity, minHeight: 150)
    }
}
