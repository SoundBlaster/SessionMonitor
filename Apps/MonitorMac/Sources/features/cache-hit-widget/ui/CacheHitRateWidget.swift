import Charts
import MonitorCore
import SwiftUI

/// A reusable privacy-safe card. The caller selects a family; no session or model identifier
/// enters this view's public API, rendered labels, or accessibility tree.
struct CacheHitRateWidget: View {
    let report: CacheHitRateWidgetReport?
    let family: CacheHitRateWidgetAppearance.Family
    let appearance: CacheHitRateWidgetAppearance
    let onOpenAnalytics: (() -> Void)?

    init(
        report: CacheHitRateWidgetReport?,
        family: CacheHitRateWidgetAppearance.Family,
        appearance: CacheHitRateWidgetAppearance = .default,
        onOpenAnalytics: (() -> Void)? = nil
    ) {
        self.report = report
        self.family = family
        self.appearance = appearance
        self.onOpenAnalytics = onOpenAnalytics
    }

    var body: some View {
        Button(action: { onOpenAnalytics?() }, label: { content })
        .buttonStyle(.plain)
        .disabled(onOpenAnalytics == nil)
        .padding(cardPadding)
        .background(.background, in: RoundedRectangle(cornerRadius: CacheHitRateWidgetLayout.cardCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: CacheHitRateWidgetLayout.cardCornerRadius)
                .stroke(.quaternary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(appearance.copy.title)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(onOpenAnalytics == nil ? "" : "Open cache analytics.")
        .accessibilityIdentifier("cacheHitRate.widget")
    }

    @ViewBuilder
    private var content: some View {
        if let report {
            VStack(alignment: .leading, spacing: 10) {
                header(report)
                switch report.availability {
                case .available:
                    chart(report)
                    if family == .large { footer(report) }
                case .partialCoverage:
                    unavailableState(report, message: "Cache coverage is partial")
                case .notApplicable:
                    unavailableState(report, message: "Cache is not applicable")
                case .noData:
                    unavailableState(report, message: appearance.copy.noDataMessage)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(appearance.copy.title).font(.headline)
                unavailableState(nil, message: appearance.copy.noDataMessage)
            }
        }
    }

    private func header(_ report: CacheHitRateWidgetReport) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(appearance.copy.title)
                    .font(family == .small ? .headline : .title3.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if family != .small {
                    Text(periodLabel(report.period)).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text(percentLabel(report.periodCacheHitRate))
                    .font(family == .small ? .title2.weight(.semibold) : .title.weight(.semibold))
                    .monospacedDigit()
                if let delta = report.comparisonDeltaPercentagePoints {
                    Label {
                        Text(deltaLabel(delta))
                    } icon: {
                        Image(systemName: "triangle.fill")
                            .rotationEffect(delta < 0 ? .degrees(180) : .zero)
                    }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(delta >= 0 ? appearance.palette.improvement : appearance.palette.degradation)
                }
                if family == .large {
                    Text(appearance.copy.comparisonLabel).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func chart(_ report: CacheHitRateWidgetReport) -> some View {
        let domain = CacheHitRateWidgetAxis.domain(for: report.buckets)
        return Chart {
            ForEach(report.buckets) { bucket in
                BarMark(
                    x: .value("Bucket", bucket.start),
                    yStart: .value("P10", bucket.lower),
                    yEnd: .value("P90", bucket.upper),
                    width: .fixed(CacheHitRateWidgetLayout.rangeWidth)
                )
                .foregroundStyle(
                    LinearGradient(colors: [appearance.palette.accent.opacity(0.75), appearance.palette.accent],
                                   startPoint: .bottom, endPoint: .top)
                )
                .cornerRadius(CacheHitRateWidgetLayout.rangeWidth / 2)

                RuleMark(
                    xStart: .value("Average start", averageStart(for: bucket)),
                    xEnd: .value("Average end", averageEnd(for: bucket)),
                    y: .value("Average", CacheHitRateWidgetChartPresentation.averageMarker(for: bucket))
                )
                .foregroundStyle(appearance.palette.average)
                .lineStyle(StrokeStyle(lineWidth: CacheHitRateWidgetLayout.averageLineWidth, lineCap: .round))

                ForEach(Array(bucket.outliers.prefix(outlierLimit)), id: \.self) { outlier in
                    PointMark(
                        x: .value("Bucket", bucket.start),
                        y: .value("Outlier", clipped(outlier.cacheHitRate, domain: domain))
                    )
                        .symbol(outlier.severity == .strong ? .circle : .circle)
                        .symbolSize(outlier.severity == .strong
                            ? CacheHitRateWidgetLayout.strongOutlierSize * CacheHitRateWidgetLayout.strongOutlierSize
                            : CacheHitRateWidgetLayout.normalOutlierSize * CacheHitRateWidgetLayout.normalOutlierSize)
                        .foregroundStyle(outlier.severity == .strong
                            ? appearance.palette.strongOutlier
                            : appearance.palette.notableOutlier.opacity(0.65))
                }
            }
        }
        .chartYScale(domain: domain)
        .chartXScale(range: .plotDimension(startPadding: xAxisEdgePadding, endPadding: xAxisEdgePadding))
        .chartXAxis { xAxis(for: report) }
        .chartYAxis { yAxis }
        .chartLegend(.hidden)
        .frame(height: chartHeight)
        .accessibilityLabel("Cache hit rate distribution")
    }

    @AxisContentBuilder private func xAxis(for report: CacheHitRateWidgetReport) -> some AxisContent {
        AxisMarks(values: CacheHitRateWidgetChartPresentation.bucketStarts(for: report)) { value in
            AxisTick()
            AxisValueLabel {
                if let date = value.as(Date.self) {
                    Text(CacheHitRateWidgetLabelFormat.bucketLabel(
                        for: date,
                        period: report.period,
                        family: family,
                        timeZoneIdentifier: report.timeZoneIdentifier
                    ))
                }
            }
        }
    }

    @AxisContentBuilder private var yAxis: some AxisContent {
        AxisMarks(position: .leading, values: .stride(by: 5)) { _ in
            if family != .small {
                AxisGridLine().foregroundStyle(.secondary.opacity(CacheHitRateWidgetLayout.gridOpacity))
            }
            AxisTick()
            if family != .small { AxisValueLabel() }
        }
    }

    private func footer(_ report: CacheHitRateWidgetReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(report.sessionCount.formatted()) sessions").font(.subheadline.weight(.semibold))
                    Text("Mixed models").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                legend
            }
        }
    }

    private var legend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { legendItems }
            VStack(alignment: .leading, spacing: 3) { legendItems }
        }
        .font(.caption2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chart legend")
    }

    @ViewBuilder private var legendItems: some View {
        Label(appearance.copy.rangeLegend, systemImage: "rectangle.portrait.fill")
            .foregroundStyle(appearance.palette.accent)
        Label(appearance.copy.averageLegend, systemImage: "minus")
            .foregroundStyle(appearance.palette.average)
        Label(appearance.copy.outlierLegend, systemImage: "circle.fill")
            .foregroundStyle(appearance.palette.strongOutlier)
    }

    private func unavailableState(_ report: CacheHitRateWidgetReport?, message: String) -> some View {
        ContentUnavailableView(
            message,
            systemImage: "chart.bar.xaxis",
            description: Text(unavailableDescription(report))
        )
            .frame(maxWidth: .infinity, minHeight: family == .small ? 90 : 120)
    }

    private var outlierLimit: Int {
        switch family {
        case .large: CacheHitRateWidgetLayout.maximumOutliers
        case .medium: 3
        case .small: 2
        }
    }

    private var accessibilityValue: String {
        guard let report else { return appearance.copy.noDataMessage }
        guard let rate = report.periodCacheHitRate else { return unavailableDescription(report) }
        let delta = report.comparisonDeltaPercentagePoints.map(deltaLabel) ?? "No previous comparison"
        return "Cache hit rate \(percentLabel(rate)) during \(periodLabel(report.period)), \(delta)."
    }

    private func unavailableDescription(_ report: CacheHitRateWidgetReport?) -> String {
        guard let report else { return "No cache data is available yet." }
        return switch report.availability {
        case .available: ""
        case let .partialCoverage(unknownObservationCount):
            "\(unknownObservationCount.formatted()) observations have unknown cache usage."
        case .notApplicable: "No cacheable input tokens are available for this period."
        case .noData: "No canonical cache data is available for this period."
        }
    }

    private func periodLabel(_ period: CacheHitRateWidgetPeriod) -> String {
        switch period {
        case .last24Hours: "Last 24 hours"
        case .last7Days: "Last 7 days"
        case .last14Days: "Last 14 days"
        case .last30Days: "Last 30 days"
        }
    }

    private func percentLabel(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(1))) + "%" } ?? "--"
    }

    private func deltaLabel(_ value: Double) -> String {
        let number = value.formatted(.number.precision(.fractionLength(1)))
        return "\(value > 0 ? "+" : "")\(number) pp"
    }

    private func clipped(_ value: Double, domain: ClosedRange<Double>) -> Double {
        min(domain.upperBound, max(domain.lowerBound, value))
    }

    private var xAxisEdgePadding: CGFloat { CacheHitRateWidgetLayout.xAxisEdgePadding }

    private var cardPadding: CGFloat {
        family == .large ? CacheHitRateWidgetLayout.cardPadding : CacheHitRateWidgetLayout.compactCardPadding
    }

    private var chartHeight: CGFloat {
        family == .small ? CacheHitRateWidgetLayout.compactChartHeight : CacheHitRateWidgetLayout.chartHeight
    }

}

private extension CacheHitRateWidget {
    func averageStart(for bucket: CacheHitRateBucket) -> Date {
        bucket.start.addingTimeInterval(-averageMarkerHalfWidth(for: bucket))
    }

    func averageEnd(for bucket: CacheHitRateBucket) -> Date {
        bucket.start.addingTimeInterval(averageMarkerHalfWidth(for: bucket))
    }

    func averageMarkerHalfWidth(for bucket: CacheHitRateBucket) -> TimeInterval {
        0.09 * bucket.end.timeIntervalSince(bucket.start)
    }
}

enum CacheHitRateWidgetAxis {
    static func domain(for buckets: [CacheHitRateBucket]) -> ClosedRange<Double> {
        let normalValues = buckets.flatMap { [$0.lower, $0.average, $0.upper] }
        let normalMinimum = normalValues.min() ?? 75
        let minimum = [75.0, 50, 25, 0].first(where: { $0 <= normalMinimum }) ?? 0
        return minimum...100
    }
}

enum CacheHitRateWidgetChartPresentation {
    static func averageMarker(for bucket: CacheHitRateBucket) -> Double {
        min(bucket.upper, max(bucket.lower, bucket.average))
    }

    static func bucketStarts(for report: CacheHitRateWidgetReport) -> [Date] {
        report.buckets.map(\.start)
    }
}
