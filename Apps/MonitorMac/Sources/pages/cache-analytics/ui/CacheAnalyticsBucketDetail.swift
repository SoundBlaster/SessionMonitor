import Foundation
import MonitorCore
import SwiftUI

struct CacheAnalyticsBucketDetail: View {
    let slot: CacheHitRateWidgetSlot?
    let report: CacheHitRateWidgetReport

    var body: some View {
        VStack(alignment: .leading, spacing: CacheHitRateWidgetLayout.textSpacing) {
            if let slot {
                Text(Self.dateLabel(slot.start, report: report)).font(.headline)
                if let bucket = slot.bucket {
                    Text("Weighted average \(percent(bucket.average)); "
                         + "range \(percent(bucket.lower))–\(percent(bucket.upper))")
                    Text("\(bucket.sampleCount) samples · \(bucket.outliers.count) outliers")
                        .foregroundStyle(.secondary)
                } else {
                    Text("No cache data for this bucket").foregroundStyle(.secondary)
                }
            } else {
                Text("Click or drag on the chart, or choose a bucket to inspect it.")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("cacheHitRate.analytics.detail")
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
