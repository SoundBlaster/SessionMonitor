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
