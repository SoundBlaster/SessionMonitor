import Charts
import MonitorCore
import SwiftUI

struct CacheHitRateWidgetChart: View {
    let report: CacheHitRateWidgetReport
    let family: CacheHitRateWidgetAppearance.Family
    let appearance: CacheHitRateWidgetAppearance

    private var slots: [CacheHitRateWidgetSlot] { CacheHitRateWidgetChartPresentation.slots(for: report) }
    private var domain: ClosedRange<Double> { CacheHitRateWidgetAxis.domain(for: report.buckets) }

    var body: some View {
        Chart {
            if family != .small {
                ForEach(labelSlots) { slot in
                    RuleMark(x: .value("Day", Double(slot.id)))
                        .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                        .foregroundStyle(Color.secondary.opacity(CacheHitRateWidgetLayout.gridOpacity))
                        .accessibilityHidden(true)
                }
            }
            ForEach(slots) { slot in
                if let bucket = slot.bucket { marks(bucket, index: Double(slot.id)) }
            }
        }
        .chartXScale(domain: -0.5...Double(max(slots.count, 1)) - 0.5, range: .plotDimension(padding: 0))
        .chartYScale(domain: domain, range: .plotDimension(padding: CacheHitRateWidgetLayout.plotVerticalInset))
        .chartXAxis(.hidden)
        .chartYAxis { yAxis }
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let anchor = proxy.plotFrame {
                    let plot = geometry[anchor]
                    let labelFamily: CacheHitRateWidgetAppearance.Family =
                        plot.width / Double(slots.count) < CacheHitRateWidgetLayout.fullLabelSlotWidth ? .small : family
                    ForEach(labelSlots) { slot in
                        if let position = proxy.position(forX: Double(slot.id)) {
                            Text(CacheHitRateWidgetLabelFormat.bucketLabel(
                                for: slot.start, period: report.period,
                                family: labelFamily, timeZoneIdentifier: report.timeZoneIdentifier))
                                .font(.caption2).foregroundStyle(.secondary)
                                .position(x: plot.minX + position,
                                          y: plot.maxY + CacheHitRateWidgetLayout.labelOffset)
                        }
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .chartPlotStyle { plot in
            plot.aspectRatio(CacheHitRateWidgetLayout.chartAspectRatio, contentMode: .fit)
        }
        .padding(.bottom, CacheHitRateWidgetLayout.labelSpace)
        .accessibilityRepresentation {
            VStack {
                ForEach(slots) { slot in
                    Text(slot.bucket.map(bucketDescription) ?? "\(dateLabel(slot.start)): no cache data")
                        .accessibilityElement(children: .ignore)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Cache hit rate distribution")
        }
    }

    @ChartContentBuilder
    private func marks(_ bucket: CacheHitRateBucket, index: Double) -> some ChartContent {
        BarMark(x: .value("Day", index), yStart: .value("P10", bucket.lower),
                yEnd: .value("P90", bucket.upper), width: .fixed(barWidth))
            .foregroundStyle(LinearGradient(
                colors: [appearance.palette.accent, appearance.palette.accent.opacity(0.65)],
                startPoint: .bottom, endPoint: .top))
            .cornerRadius(CacheHitRateWidgetLayout.rangeWidth)
            .accessibilityLabel(bucketDescription(bucket))
        if bucket.lower == bucket.upper {
            PointMark(x: .value("Day", index), y: .value("Range", bucket.lower))
                .symbol(.circle).symbolSize(CacheHitRateWidgetLayout.minimumRangeArea)
                .foregroundStyle(appearance.palette.accent)
                .accessibilityHidden(true)
        }
        // Weighted mean is not generally inside unweighted P10–P90. Never falsify it by clamping to the range.
        if bucket.average < bucket.lower || bucket.average > bucket.upper {
            RuleMark(x: .value("Day", index),
                     yStart: .value("Range edge", min(bucket.upper, max(bucket.lower, bucket.average))),
                     yEnd: .value("Mean", clipped(bucket.average)))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                .foregroundStyle(appearance.palette.average.opacity(0.6))
                .accessibilityHidden(true)
        }
        RuleMark(xStart: .value("Mean start", index - CacheHitRateWidgetLayout.averageSlotHalfWidth),
                 xEnd: .value("Mean end", index + CacheHitRateWidgetLayout.averageSlotHalfWidth),
                 y: .value("Mean", clipped(CacheHitRateWidgetChartPresentation.averageMarker(for: bucket))))
            .lineStyle(StrokeStyle(lineWidth: family == .large ? 3 : 2, lineCap: .round))
            .foregroundStyle(appearance.palette.average)
            .accessibilityLabel("Weighted average \(bucket.average.formatted()) percent")
            .annotation(position: .top, spacing: 2) {
                if bucket.average < domain.lowerBound {
                    Image(systemName: "arrow.down").font(.caption2).foregroundStyle(appearance.palette.average)
                }
            }
        ForEach(Array(bucket.outliers.prefix(outlierLimit).enumerated()), id: \.offset) { _, outlier in
            PointMark(x: .value("Day", index), y: .value("Outlier", clipped(outlier.cacheHitRate)))
                .symbolSize(CacheHitRateWidgetLayout.outlierArea)
                .symbol(outlier.cacheHitRate < domain.lowerBound ? .triangle : .circle)
                .foregroundStyle(outlier.severity == .strong
                    ? appearance.palette.strongOutlier : appearance.palette.notableOutlier.opacity(0.65))
                .accessibilityLabel("Outlier \(outlier.cacheHitRate.formatted()) percent")
        }
    }

    @AxisContentBuilder private var yAxis: some AxisContent {
        AxisMarks(position: .leading, values: CacheHitRateWidgetAxis.ticks(for: domain)) { _ in
            if family != .small {
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    .foregroundStyle(Color.secondary.opacity(CacheHitRateWidgetLayout.gridOpacity))
                AxisValueLabel()
            }
        }
    }

    private var barWidth: CGFloat {
        let base = family == .small ? CacheHitRateWidgetLayout.compactRangeWidth : CacheHitRateWidgetLayout.rangeWidth
        return base * min(1, 7 / CGFloat(max(slots.count, 1)))
    }

    private var labelSlots: [CacheHitRateWidgetSlot] {
        let stride = max(1, Int(ceil(Double(slots.count) / 8)))
        return slots.filter { $0.id.isMultiple(of: stride) }
    }

    private var outlierLimit: Int { family == .large ? 4 : family == .medium ? 3 : 2 }
    private func clipped(_ value: Double) -> Double { min(domain.upperBound, max(domain.lowerBound, value)) }

    private func dateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: report.timeZoneIdentifier) ?? .gmt
        formatter.setLocalizedDateFormatFromTemplate("MMM d HHmm")
        return formatter.string(from: date)
    }

    private func bucketDescription(_ bucket: CacheHitRateBucket) -> String {
        let date = dateLabel(bucket.start)
        return "\(date), average \(bucket.average.formatted()) percent, "
            + "typical range \(bucket.lower.formatted()) to \(bucket.upper.formatted()) percent, "
            + "\(bucket.outliers.count) outliers: "
            + bucket.outliers.map { "\($0.cacheHitRate.formatted()) percent" }.joined(separator: ", ")
    }
}
