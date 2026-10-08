import Foundation
import MonitorCore

/// What the chart says about one calendar slot. It carries counts and percentages only, never a session
/// or model identity (the SM-311 privacy contract).
enum CacheHitRateWidgetBucketDetail {
    static let hint = "Hover a bar for details"

    /// The slot nearest to a chart x position; `nil` outside the plotted slots.
    static func slotID(forX position: Double, slotCount: Int) -> Int? {
        guard slotCount > 0, position.isFinite, position >= -0.5, position < Double(slotCount) - 0.5 else {
            return nil
        }
        return min(slotCount - 1, max(0, Int(position.rounded())))
    }

    static func text(
        for slot: CacheHitRateWidgetSlot,
        report: CacheHitRateWidgetReport,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let when = dateLabel(slot.start, period: report.period,
                             timeZoneIdentifier: report.timeZoneIdentifier, locale: locale)
        guard let bucket = slot.bucket else { return "\(when) · no cache data" }
        let range = bucket.usesMinMaxFallback ? "min–max" : "typical"
        return [
            when,
            "avg \(number(bucket.average, digits: 1, locale))%",
            "\(range) \(number(bucket.lower, digits: 0, locale))–\(number(bucket.upper, digits: 0, locale))%",
            count(bucket.sampleCount, "session", locale)
        ].joined(separator: " · ")
    }

    /// The full sentence for assistive technologies, including outliers.
    static func accessibilityText(
        for slot: CacheHitRateWidgetSlot,
        report: CacheHitRateWidgetReport,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let summary = text(for: slot, report: report, locale: locale)
        guard let bucket = slot.bucket, !bucket.outliers.isEmpty else { return summary }
        return summary + ", " + count(bucket.outliers.count, "outlier", locale)
    }

    private static func dateLabel(
        _ date: Date, period: CacheHitRateWidgetPeriod, timeZoneIdentifier: String, locale: Locale
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .gmt
        formatter.setLocalizedDateFormatFromTemplate(period == .last24Hours ? "MMMdjmm" : "EEEMMMd")
        return formatter.string(from: date)
    }

    private static func number(_ value: Double, digits: Int, _ locale: Locale) -> String {
        String(format: "%.\(digits)f", locale: locale, value)
    }

    private static func count(_ value: Int, _ noun: String, _ locale: Locale) -> String {
        "\(value) \(noun)\(value == 1 ? "" : "s")"
    }
}
