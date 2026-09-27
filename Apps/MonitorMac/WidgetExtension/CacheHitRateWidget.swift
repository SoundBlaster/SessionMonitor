import MonitorCore
import SwiftUI
import WidgetKit

struct SessionMonitorCacheHitRateWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: WidgetSharedSnapshot.cacheWidgetKind,
            provider: SessionMonitorWidgetProvider()
        ) { entry in
            SessionMonitorCacheHitRateWidgetView(entry: entry)
        }
        .configurationDisplayName("Cache Hit Rate")
        .description("Cache hit rate, typical range, and anonymous outliers for the last seven days.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct SessionMonitorCacheHitRateWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SessionMonitorWidgetEntry

    var body: some View {
        Group {
            if let cache = entry.snapshot?.cache {
                CacheWidgetContent(cache: cache, entry: entry, family: family)
            } else {
                WidgetUnavailableState(
                    title: "Cache data unavailable",
                    detail: "Open SessionMonitor to refresh the shared snapshot."
                )
            }
        }
        .padding(family == .systemSmall ? WidgetDesignTokens.compactInset : WidgetDesignTokens.contentInset)
        .containerBackground(.background, for: .widget)
        .widgetURL(WidgetDeepLinkRoute.cacheHitRate.url)
    }
}

private struct CacheWidgetContent: View {
    let cache: WidgetCachePeriodSnapshot
    let entry: SessionMonitorWidgetEntry
    let family: WidgetFamily

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetDesignTokens.sectionSpacing) {
            CacheWidgetHeader(cache: cache, family: family)
            if showsBucketChart {
                CacheWidgetRangeChart(buckets: cache.buckets, family: family)
                    .frame(height: chartHeight)
                if cache.availability == .partial {
                    Label("Partial observations", systemImage: "exclamationmark.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                CacheWidgetStatus(cache: cache)
                    .frame(maxHeight: .infinity)
            }
            if family == .systemLarge {
                CacheWidgetLegend(sessionCount: cache.sessionCount)
            }
            Spacer(minLength: 0)
            WidgetUpdatedLabel(entry: entry)
        }
        .accessibilityElement(children: .contain)
    }

    private var chartHeight: CGFloat {
        switch family {
        case .systemSmall: WidgetDesignTokens.compactChartHeight
        case .systemLarge: WidgetDesignTokens.largeChartHeight
        default: WidgetDesignTokens.mediumChartHeight
        }
    }

    private var showsBucketChart: Bool {
        !cache.buckets.isEmpty && cache.availability != .noData && cache.availability != .notApplicable
    }
}

private struct CacheWidgetHeader: View {
    let cache: WidgetCachePeriodSnapshot
    let family: WidgetFamily

    var body: some View {
        HStack(alignment: .top, spacing: WidgetDesignTokens.chartSpacing) {
            WidgetTitle(title: "Cache Hit Rate", subtitle: family == .systemSmall ? nil : "Last 7 days")
            Spacer(minLength: 2)
            VStack(alignment: .trailing, spacing: 2) {
                Text(WidgetFormatting.percentage(cache.hitRate))
                    .font(family == .systemSmall ? .title2 : .title.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                if let delta = cache.comparisonDeltaPercentagePoints {
                    CacheWidgetDelta(value: delta, isCompact: family == .systemSmall)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cache hit rate \(WidgetFormatting.percentage(cache.hitRate)) during last 7 days")
    }
}

private struct CacheWidgetDelta: View {
    let value: Double
    let isCompact: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: value > 0 ? "triangle.fill" : (value < 0 ? "triangle.fill" : "minus"))
                .font(.system(size: WidgetDesignTokens.outlierDiameter + 2, weight: .bold))
                .rotationEffect(value < 0 ? .degrees(180) : .zero)
            Text("\(value > 0 ? "+" : "")\(value.formatted(.number.precision(.fractionLength(1)))) pp")
                .font((isCompact ? Font.caption2 : Font.caption).weight(.semibold).monospacedDigit())
        }
        .foregroundStyle(color)
        .accessibilityLabel(accessibilityLabel)
    }

    private var color: Color {
        if value > 0 { return WidgetDesignTokens.improvement }
        if value < 0 { return WidgetDesignTokens.warning }
        return .secondary
    }

    private var accessibilityLabel: String {
        let change = value > 0 ? "Improved" : (value < 0 ? "Declined" : "Unchanged")
        let amount = value.formatted(.number.precision(.fractionLength(1)))
        return "\(change) by \(amount) percentage points"
    }
}

private struct CacheWidgetStatus: View {
    let cache: WidgetCachePeriodSnapshot

    private var message: (String, String) {
        switch cache.availability {
        case .available: ("No bucket data", "Cache hit rate is available for this period.")
        case .partial: ("Partial cache data", "Some observations do not have cache coverage.")
        case .notApplicable: ("Cache not applicable", "No cacheable input was recorded.")
        case .noData: ("No cache data", "SessionMonitor has not recorded cache observations yet.")
        }
    }

    var body: some View {
        WidgetUnavailableState(title: message.0, detail: message.1)
    }
}

private struct CacheWidgetLegend: View {
    let sessionCount: Int

    var body: some View {
        HStack(spacing: WidgetDesignTokens.sectionSpacing) {
            Label("P10–P90", systemImage: "capsule.portrait.fill")
            Label("Average", systemImage: "minus")
            Label("Outlier", systemImage: "circle.fill")
            Spacer(minLength: 0)
            Text("\(sessionCount.formatted()) sessions")
                .foregroundStyle(.secondary)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .combine)
    }
}

private struct CacheWidgetRangeChart: View {
    let buckets: [WidgetCacheBucket]
    let family: WidgetFamily

    private var showsAxis: Bool { family != .systemSmall }
    private var barWidth: CGFloat {
        family == .systemSmall ? WidgetDesignTokens.compactBarWidth : WidgetDesignTokens.barWidth
    }

    var body: some View {
        GeometryReader { geometry in
            let axisWidth = showsAxis ? WidgetDesignTokens.axisLabelWidth : 0
            let plotWidth = max(0, geometry.size.width - axisWidth)
            let plotHeight = max(0, geometry.size.height - WidgetDesignTokens.chartLabelHeight(for: family))
            HStack(alignment: .top, spacing: WidgetDesignTokens.axisGutterSpacing) {
                if showsAxis {
                    axisLabels(height: plotHeight).frame(width: axisWidth, height: geometry.size.height)
                }
                plot(width: plotWidth, height: geometry.size.height, plotHeight: plotHeight)
                    .frame(width: plotWidth, height: geometry.size.height)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chartAccessibilityLabel)
    }

    private func axisLabels(height: CGFloat) -> some View {
        GeometryReader { geometry in
            ForEach(WidgetDesignTokens.chartAxisTicks, id: \.self) { value in
                Text("\(value)")
                    .font(.system(size: WidgetDesignTokens.axisFontSize, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .position(x: geometry.size.width / 2, y: axisPosition(for: value, height: height))
            }
        }
    }

    private func axisPosition(for value: Double, height: CGFloat) -> CGFloat {
        let position = yPosition(value, height: height)
        let upperInset = WidgetDesignTokens.chartAxisInset
        let lowerInset = max(upperInset, height - upperInset)
        return min(max(upperInset, position), lowerInset)
    }

    private func plot(width: CGFloat, height: CGFloat, plotHeight: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            grid(width: width, height: plotHeight)
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(buckets.sorted { $0.startsAt < $1.startsAt })) { bucket in
                    CacheWidgetBucketMark(bucket: bucket, family: family, barWidth: barWidth)
                        .frame(maxWidth: .infinity, maxHeight: height)
                }
            }
            .frame(width: width, height: height)
        }
    }

    private func grid(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(WidgetDesignTokens.chartAxisTicks, id: \.self) { value in
                Path { path in
                    let yPosition = yPosition(value, height: height)
                    path.move(to: CGPoint(x: 0, y: yPosition))
                    path.addLine(to: CGPoint(x: width, y: yPosition))
                }
                .stroke(WidgetDesignTokens.grid, style: StrokeStyle(
                    lineWidth: value == WidgetDesignTokens.chartMinimum
                        ? WidgetDesignTokens.chartBaselineLineWidth : WidgetDesignTokens.chartGridLineWidth,
                    dash: [WidgetDesignTokens.chartGridDashLength, WidgetDesignTokens.chartGridDashGap]
                ))
            }
        }
    }

    private func yPosition(_ value: Double, height: CGFloat) -> CGFloat {
        let normalized = (value - WidgetDesignTokens.chartMinimum)
            / (WidgetDesignTokens.chartMaximum - WidgetDesignTokens.chartMinimum)
        return height * CGFloat(1 - normalized)
    }

    private var chartAccessibilityLabel: String {
        "Daily cache hit rate, typical range and average for the last seven days. "
            + "Outlier session identities are hidden."
    }
}

private struct CacheWidgetBucketMark: View {
    let bucket: WidgetCacheBucket
    let family: WidgetFamily
    let barWidth: CGFloat

    private var markerWidth: CGFloat {
        family == .systemLarge ? WidgetDesignTokens.largeAverageMarkerWidth : WidgetDesignTokens.averageMarkerWidth
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Capsule()
                    .fill(rangeGradient)
                    .frame(width: barWidth, height: barHeight)
                    .position(x: geometry.size.width / 2,
                              y: barMidpoint)
                Rectangle()
                    .fill(WidgetDesignTokens.averageMarker)
                    .frame(width: markerWidth, height: WidgetDesignTokens.averageMarkerHeight)
                    .position(x: geometry.size.width / 2, y: yPosition(bucket.average, height: plotHeight))
                ForEach(Array(bucket.outliers.prefix(outlierLimit).enumerated()), id: \.offset) { _, outlier in
                    CacheWidgetOutlierMark(outlier: outlier)
                        .position(x: geometry.size.width / 2,
                                  y: yPosition(outlier.hitRate, height: plotHeight))
                }
                Text(WidgetFormatting.bucketTitle(bucket.startsAt, family: family))
                    .font(.system(size: family == .systemLarge
                        ? WidgetDesignTokens.largeAxisFontSize : WidgetDesignTokens.axisFontSize))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .position(x: geometry.size.width / 2, y: plotHeight + labelHeight / 2)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var labelHeight: CGFloat { WidgetDesignTokens.chartLabelHeight(for: family) }
    private var plotHeight: CGFloat { max(0, WidgetDesignTokens.chartHeight(for: family) - labelHeight) }
    private var rangeGradient: LinearGradient {
        LinearGradient(
            colors: [WidgetDesignTokens.accent.opacity(0.78), WidgetDesignTokens.accent],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var barHeight: CGFloat {
        let lower = yPosition(bucket.lower, height: plotHeight)
        let upper = yPosition(bucket.upper, height: plotHeight)
        return max(WidgetDesignTokens.minimumRangeHeight, lower - upper)
    }

    private var barMidpoint: CGFloat {
        let upper = yPosition(bucket.upper, height: plotHeight)
        let lower = yPosition(bucket.lower, height: plotHeight)
        return (upper + lower) / 2
    }
    private var outlierLimit: Int {
        switch family {
        case .systemSmall: WidgetDesignTokens.smallOutlierLimit
        case .systemLarge: WidgetDesignTokens.largeOutlierLimit
        default: WidgetDesignTokens.mediumOutlierLimit
        }
    }

    private func yPosition(_ value: Double, height: CGFloat) -> CGFloat {
        let normalized = (value - WidgetDesignTokens.chartMinimum)
            / (WidgetDesignTokens.chartMaximum - WidgetDesignTokens.chartMinimum)
        return height * CGFloat(1 - min(1, max(0, normalized)))
    }

    private var accessibilityLabel: String {
        let day = WidgetFormatting.bucketTitle(bucket.startsAt, family: family)
        let average = WidgetFormatting.percentage(bucket.average)
        let lower = WidgetFormatting.percentage(bucket.lower)
        let upper = WidgetFormatting.percentage(bucket.upper)
        return "\(day), average \(average), typical range \(lower) to \(upper), \(bucket.outliers.count) outliers"
    }
}

private struct CacheWidgetOutlierMark: View {
    let outlier: WidgetCacheOutlier

    private var isOutsideAxis: Bool {
        outlier.hitRate < WidgetDesignTokens.chartMinimum || outlier.hitRate > WidgetDesignTokens.chartMaximum
    }

    private var color: Color {
        outlier.severity == .strong ? WidgetDesignTokens.warning : WidgetDesignTokens.notableOutlier
    }

    var body: some View {
        Group {
            if isOutsideAxis {
                Image(systemName: "triangle.fill")
                    .font(.system(size: WidgetDesignTokens.warningOutlierDiameter))
                    .rotationEffect(outlier.hitRate < WidgetDesignTokens.chartMinimum ? .degrees(180) : .zero)
            } else {
                Circle()
                    .frame(width: diameter, height: diameter)
            }
        }
        .foregroundStyle(color)
        .accessibilityHidden(true)
    }

    private var diameter: CGFloat {
        outlier.severity == .strong
            ? WidgetDesignTokens.warningOutlierDiameter
            : WidgetDesignTokens.outlierDiameter
    }
}

extension WidgetDesignTokens {
    static func chartHeight(for family: WidgetFamily) -> CGFloat {
        switch family {
        case .systemSmall: compactChartHeight
        case .systemLarge: largeChartHeight
        default: mediumChartHeight
        }
    }

    static func chartLabelHeight(for family: WidgetFamily) -> CGFloat {
        family == .systemSmall ? compactBucketLabelHeight : bucketLabelHeight
    }
}
