import Foundation
import MonitorCore
import Observation

@MainActor
@Observable
final class CacheHitRateWidgetSettings {
    static let periodStorageKey = "cacheHitRateWidget.period"

    private(set) var period: CacheHitRateWidgetPeriod
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        period = defaults.string(forKey: Self.periodStorageKey)
            .flatMap(CacheHitRateWidgetPeriod.init(rawValue:)) ?? .last7Days
    }

    func selectPeriod(_ period: CacheHitRateWidgetPeriod) {
        guard self.period != period else { return }
        self.period = period
        defaults.set(period.rawValue, forKey: Self.periodStorageKey)
    }
}

enum CacheHitRateWidgetLabelFormat {
    static func bucketLabel(
        for date: Date,
        period: CacheHitRateWidgetPeriod,
        family: CacheHitRateWidgetAppearance.Family,
        timeZoneIdentifier: String,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current

        switch period {
        case .last24Hours:
            formatter.setLocalizedDateFormatFromTemplate("j")
        case .last7Days, .last14Days, .last30Days:
            formatter.setLocalizedDateFormatFromTemplate(family == .small ? "EEEEE" : "EEE")
        }

        return formatter.string(from: date)
    }
}

enum CacheHitRateWidgetRefreshSchedule {
    /// Refreshes at local hour boundaries so rolling windows age out records and hourly buckets advance.
    static func nextRefresh(after date: Date, timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let hourStart = calendar.dateInterval(of: .hour, for: date)?.start ?? date
        return calendar.date(byAdding: .hour, value: 1, to: hourStart) ?? date.addingTimeInterval(3_600)
    }
}
