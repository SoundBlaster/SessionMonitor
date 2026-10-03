import MonitorCore
import SwiftUI

struct CacheAnalyticsPage: View {
    let presentation: CacheAnalyticsPresentation
    @AppStorage(UsageChartPaletteSelection.storageKey)
    private var paletteValue = UsageChartPaletteSelection.system.rawValue
    @State private var viewport = CacheAnalyticsViewport()
    @State private var selection: Double?

    private var appearance: CacheHitRateWidgetAppearance {
        .init(palette: .init(chart: UsageChartPaletteSelection(rawValue: paletteValue)?.palette ?? .system),
              copy: .default)
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                content(chartHeight: max(CacheAnalyticsLayout.minimumChartHeight,
                                         geometry.size.height * CacheAnalyticsLayout.chartHeightFraction))
            }
        }
        .frame(minWidth: 440, minHeight: 480)
        .accessibilityIdentifier("cacheHitRate.analytics")
        .onChange(of: presentation.sourceID) { _, _ in resetViewport() }
        .onChange(of: presentation.report?.periodStart) { _, _ in resetViewport() }
        .onChange(of: presentation.report?.periodEnd) { _, _ in resetViewport() }
        .onChange(of: presentation.accountLabel) { _, _ in resetViewport() }
    }

    private func content(chartHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: CacheHitRateWidgetLayout.cardPadding) {
            if let report = presentation.report {
                Text(presentation.accountLabel).font(.caption).foregroundStyle(.secondary)
                if report.availability == .available {
                    CacheHitRateWidgetHeader(report: report, family: .large, appearance: appearance,
                                             periodTitle: presentation.periodTitle)
                    interactiveChart(report, height: chartHeight)
                } else {
                    CacheHitRateWidget(report: report, family: .large, appearance: appearance,
                                       containerStyle: .embedded, periodTitle: presentation.periodTitle)
                }
            } else {
                ContentUnavailableView("No cache data", systemImage: "chart.bar.xaxis",
                    description: Text("Cache data is loading or unavailable for the selected scope."))
            }
        }
        .padding(CacheHitRateWidgetLayout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func interactiveChart(_ report: CacheHitRateWidgetReport, height: CGFloat) -> some View {
        let slots = CacheHitRateWidgetChartPresentation.slots(for: report)
        return VStack(alignment: .leading, spacing: CacheHitRateWidgetLayout.headerSpacing) {
            CacheAnalyticsBucketDetail(slot: viewport.selectedSlot(selection, slots: slots), report: report)
            CacheAnalyticsControls(viewport: $viewport, selection: $selection, slots: slots)
            CacheHitRateWidgetChart(report: report, family: .large, appearance: appearance,
                                    preservesAspectRatio: false,
                                    viewport: viewport.domain(slotCount: slots.count), selection: $selection,
                                    interactionViewport: $viewport)
                .frame(height: height)
                .transaction { $0.animation = nil }
            Text("Range (P10 – P90) · Weighted average · Outliers")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func resetViewport() {
        viewport = CacheAnalyticsViewport()
        selection = nil
    }
}

enum CacheAnalyticsLayout {
    static let metricColumnWidth: CGFloat = 130
    static let detailCornerRadius: CGFloat = 12
    static let detailBackgroundOpacity = 0.08
    static let minimumChartHeight: CGFloat = 260
    static let chartHeightFraction = 0.55
}
