import MonitorCore
import SwiftUI

struct SessionDetailView: View {
    let session: SessionSummary
    let query: UsageQuery
    let timelineModel: RequestTimelineModel
    let provider: SessionReportContextProvider
    var chartPalette: UsageChartPalette = .system

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                SessionSummaryView(session: session, provider: provider)
                    .id(session.id)
                if timelineModel.errorMessage == nil, let timeline = timelineModel.timeline {
                    ContextAnatomyView(timeline: timeline, timeZone: timelineModel.displayTimeZone,
                                       palette: chartPalette)
                        .id(timeline.sessionID)
                }
                RequestTimelineView(model: timelineModel, query: query, palette: chartPalette)
            }
            .padding(DesignTokens.Layout.pageInset)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}
