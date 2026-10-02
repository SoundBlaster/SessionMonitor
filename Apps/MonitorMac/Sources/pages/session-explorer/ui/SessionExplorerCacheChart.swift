import Foundation
import MonitorCore
import SwiftUI

struct SessionExplorerCacheChart: View {
    let model: SessionExplorerModel
    let reportScope: ReportScopeModel
    let settings: CacheHitRateWidgetSettings
    let chartPalette: UsageChartPalette
    let analytics: CacheAnalyticsPresentation?
    @Environment(\.openWindow) private var openWindow
    @State private var analyticsSourceID = UUID()

    var body: some View {
        CacheHitRateWidget(
            report: currentReport,
            family: .medium,
            appearance: CacheHitRateWidgetAppearance(
                palette: CacheHitRateWidgetAppearance.Palette(chart: chartPalette), copy: .default
            ),
            containerStyle: .embedded,
            periodTitle: reportScope.preset == .all ? nil : reportScope.title,
            onOpenAnalytics: {
                analytics?.open(sourceID: analyticsSourceID, report: currentReport,
                                     periodTitle: reportScope.preset == .all ? nil : reportScope.title,
                                     accountLabel: reportScope.accountLabel)
                openWindow(id: CacheAnalyticsPresentation.windowID)
            }
        )
        .padding(SessionExplorerSidebarLayout.sectionInset)
        .frame(height: SessionExplorerSidebarLayout.chartHeight, alignment: .topLeading)
        .clipped()
        .onChange(of: model.cacheHitRateWidgetReport) { _, _ in updateAnalytics() }
        .onChange(of: sidebarChartPeriod) { _, _ in updateAnalytics() }
        .onChange(of: reportScope.accountLabel) { _, _ in updateAnalytics() }
        .onChange(of: model.query) { _, _ in
            analytics?.update(sourceID: analyticsSourceID, report: nil,
                                   periodTitle: reportScope.title, accountLabel: reportScope.accountLabel)
        }
        .task(id: CacheHitRateWidgetLoadID(
            period: sidebarChartPeriod,
            revision: model.snapshot?.watermark.revision,
            query: model.query
        )) {
            guard model.snapshot != nil else { return }
            while !Task.isCancelled {
                let timeZone = TimeZone(identifier: model.query.timeZoneIdentifier) ?? .current
                await model.loadCacheHitRateWidget(
                    period: sidebarChartPeriod,
                    timeZone: timeZone,
                    followsReportScope: reportScope.preset != .all
                )
                guard !Task.isCancelled else { return }
                updateAnalytics()
                let nextRefresh = CacheHitRateWidgetRefreshSchedule.nextRefresh(after: Date(), timeZone: timeZone)
                do {
                    try await Task.sleep(for: .seconds(nextRefresh.timeIntervalSinceNow))
                } catch {
                    return
                }
            }
        }
    }

    private var currentReport: CacheHitRateWidgetReport? {
        guard model.cacheHitRateWidgetQuery == model.query,
              model.cacheHitRateWidgetReport?.period == sidebarChartPeriod else { return nil }
        return model.cacheHitRateWidgetReport
    }

    private func updateAnalytics() {
        analytics?.update(sourceID: analyticsSourceID, report: currentReport,
                               periodTitle: reportScope.preset == .all ? nil : reportScope.title,
                               accountLabel: reportScope.accountLabel)
    }

    private var sidebarChartPeriod: CacheHitRateWidgetPeriod {
        switch reportScope.preset {
        case .all: settings.period
        case .today: .last24Hours
        case .lastSevenDays: .last7Days
        case .lastThirtyDays: .last30Days
        }
    }

}

private struct CacheHitRateWidgetLoadID: Hashable {
    let period: CacheHitRateWidgetPeriod
    let revision: Int64?
    let query: UsageQuery
}
