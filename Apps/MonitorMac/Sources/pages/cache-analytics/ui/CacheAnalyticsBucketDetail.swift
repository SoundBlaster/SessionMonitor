import Foundation
import MonitorCore
import SwiftUI

struct CacheAnalyticsBucketDetail: View {
    let slot: CacheHitRateWidgetSlot?
    let report: CacheHitRateWidgetReport

    var body: some View {
        cardContent
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(CacheAnalyticsLayout.detailBackgroundOpacity),
                        in: RoundedRectangle(cornerRadius: CacheAnalyticsLayout.detailCornerRadius))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
            .accessibilityIdentifier("cacheHitRate.analytics.detail")
    }

    @ViewBuilder private var cardContent: some View {
        if let slot {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: CacheHitRateWidgetLayout.headerSpacing) {
                    intervalSummary(slot).fixedSize(horizontal: true, vertical: false)
                    if let bucket = slot.bucket {
                        metricsRow(bucket).fixedSize(horizontal: true, vertical: false)
                    } else {
                        noDataLabel.fixedSize(horizontal: true, vertical: false)
                    }
                }
                .frame(minWidth: CacheAnalyticsLayout.singleRowContentWidth)
                .padding(CacheHitRateWidgetLayout.cardPadding)
                .frame(height: CacheAnalyticsLayout.detailCardHeight, alignment: .leading)

                VStack(alignment: .leading, spacing: CacheHitRateWidgetLayout.headerSpacing) {
                    intervalSummary(slot)
                    if let bucket = slot.bucket {
                        metricsGrid(bucket)
                    } else {
                        noDataLabel
                    }
                }
                .padding(CacheHitRateWidgetLayout.cardPadding)
                .frame(minHeight: CacheAnalyticsLayout.compactDetailCardHeight, alignment: .leading)
            }
        } else {
            ViewThatFits(in: .horizontal) {
                unselectedPrompt
                    .frame(minWidth: CacheAnalyticsLayout.singleRowContentWidth)
                    .padding(CacheHitRateWidgetLayout.cardPadding)
                    .frame(height: CacheAnalyticsLayout.detailCardHeight, alignment: .leading)

                unselectedPrompt
                    .padding(CacheHitRateWidgetLayout.cardPadding)
                    .frame(minHeight: CacheAnalyticsLayout.compactDetailCardHeight, alignment: .leading)
            }
        }
    }

    private var unselectedPrompt: some View {
        VStack(alignment: .leading, spacing: CacheHitRateWidgetLayout.headerSpacing) {
            Text("Select an interval").font(.headline)
            Text("Click a bucket to pin its weighted average, range, outliers and sample count here.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func intervalSummary(_ slot: CacheHitRateWidgetSlot) -> some View {
        VStack(alignment: .leading, spacing: CacheHitRateWidgetLayout.textSpacing) {
            Text("Selected interval").font(.caption).foregroundStyle(.secondary)
            Text(Self.dateLabel(slot.start, report: report)).font(.headline)
            if let bucket = slot.bucket {
                Text("Until \(Self.dateLabel(bucket.end, report: report))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var noDataLabel: some View {
        Text("No cache data for this interval")
            .font(.title3.weight(.semibold)).foregroundStyle(.secondary)
    }

    private func metricsRow(_ bucket: CacheHitRateBucket) -> some View {
        HStack(alignment: .center, spacing: CacheHitRateWidgetLayout.headerSpacing) {
            metric("Weighted average", value: percent(bucket.average), prominent: true)
            metric(bucket.usesMinMaxFallback ? "Min–max range" : "Typical range · P10–P90",
                   value: "\(percent(bucket.lower))–\(percent(bucket.upper))")
            metric("Outliers", value: bucket.outliers.count.formatted())
            metric("Samples", value: bucket.sampleCount.formatted())
        }
    }

    private func metricsGrid(_ bucket: CacheHitRateBucket) -> some View {
        LazyVGrid(columns: metricColumns, alignment: .leading,
                  spacing: CacheHitRateWidgetLayout.headerSpacing) {
            metric("Weighted average", value: percent(bucket.average), prominent: true)
            metric(bucket.usesMinMaxFallback ? "Min–max range" : "Typical range · P10–P90",
                   value: "\(percent(bucket.lower))–\(percent(bucket.upper))")
            metric("Outliers", value: bucket.outliers.count.formatted())
            metric("Samples", value: bucket.sampleCount.formatted())
        }
    }

    private var accessibilitySummary: String {
        guard let slot else {
            return "Select an interval. Click a bucket or use previous and next interval buttons to inspect metrics."
        }
        let date = Self.dateLabel(slot.start, report: report)
        guard let bucket = slot.bucket else { return "Selected interval, \(date). No cache data for this interval." }
        let end = Self.dateLabel(bucket.end, report: report)
        let range = bucket.usesMinMaxFallback ? "Min–max range" : "Typical range, P10 to P90"
        return "Selected interval, \(date), until \(end). Weighted average \(percent(bucket.average)). "
            + "\(range), \(percent(bucket.lower)) to \(percent(bucket.upper)). "
            + "\(bucket.outliers.count) outliers. \(bucket.sampleCount) samples."
    }

    private var metricColumns: [GridItem] {
        [GridItem(.adaptive(minimum: CacheAnalyticsLayout.metricColumnWidth), alignment: .leading)]
    }

    private func metric(_ title: String, value: String, prominent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: CacheHitRateWidgetLayout.textSpacing) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(prominent ? .largeTitle.weight(.semibold) : .title3.weight(.semibold))
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    static func dateLabel(_ date: Date, report: CacheHitRateWidgetReport) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: report.timeZoneIdentifier) ?? .gmt
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d HHmm z")
        return formatter.string(from: date)
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + "%"
    }
}
