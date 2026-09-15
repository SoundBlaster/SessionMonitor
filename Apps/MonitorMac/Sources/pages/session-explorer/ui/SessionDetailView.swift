import MonitorCore
import SpecificationKit
import SwiftUI

struct SessionDetailView: View {
    let session: SessionSummary
    let query: UsageQuery
    let timelineModel: RequestTimelineModel
    @ObservedSatisfies<SessionReportSnapshot> private var hasCompleteCacheCoverage: Bool

    init(session: SessionSummary, query: UsageQuery, timelineModel: RequestTimelineModel,
         provider: SessionReportContextProvider) {
        self.session = session
        self.query = query
        self.timelineModel = timelineModel
        _hasCompleteCacheCoverage = ObservedSatisfies(provider: provider, using: DisplayedCacheCoverageSpec())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(session.model.isEmpty ? "Unknown model" : session.model)
                        .font(.largeTitle.bold())
                    Text(session.id)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Label {
                    Text("Canonical usage only. Legacy token_count records are excluded from these totals.")
                } icon: {
                    Image(systemName: "info.circle")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), alignment: .leading)],
                          alignment: .leading, spacing: 14) {
                    metric("Requests", value: session.totals.requests.formatted())
                    metric("Input tokens", value: session.totals.inputTokens.formatted())
                    metric("Output tokens", value: session.totals.outputTokens.formatted())
                    metric("Known cached input", value: session.totals.cachedInputTokens.formatted())
                }

                VStack(alignment: .leading, spacing: 14) {
                    Label("Cache coverage", systemImage: "chart.pie")
                        .font(.title2.bold())
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(cachePercentage)
                            .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                        Text("cache hit ratio")
                            .foregroundStyle(.secondary)
                    }
                    Text(cacheHit.explanation)
                        .foregroundStyle(.secondary)
                    if session.totals.unknownCacheRequests > 0 {
                        Label("\(session.totals.unknownCacheRequests.formatted()) requests have unknown cache usage",
                              systemImage: "questionmark.circle")
                            .foregroundStyle(.orange)
                    }
                    Text("Cached input tokens ÷ input tokens. A percentage is shown only when "
                         + "every request has cache data and input is greater than zero.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))

                RequestTimelineView(model: timelineModel, query: query)
            }
            .padding(28)
            .frame(maxWidth: 960, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var cachePercentage: String {
        guard hasCompleteCacheCoverage else { return "—" }
        return cacheHit.value
    }

    private var cacheHit: SessionCacheHitPresentation {
        SessionCacheHitPresentation(totals: session.totals)
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.callout).foregroundStyle(.secondary)
            Text(value).font(.title2.bold().monospacedDigit())
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}
