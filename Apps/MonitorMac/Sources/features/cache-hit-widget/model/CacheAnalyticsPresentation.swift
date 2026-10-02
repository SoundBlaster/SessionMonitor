import Foundation
import MonitorCore
import Observation

/// The scene follows the explorer that last opened it, never an unrelated window.
@MainActor @Observable
final class CacheAnalyticsPresentation {
    static let windowID = "cache-analytics"
    private(set) var sourceID: UUID?
    private(set) var report: CacheHitRateWidgetReport?
    private(set) var periodTitle: String?
    private(set) var accountLabel = "All accounts"

    func open(sourceID: UUID, report: CacheHitRateWidgetReport?, periodTitle: String?, accountLabel: String) {
        self.sourceID = sourceID
        update(sourceID: sourceID, report: report, periodTitle: periodTitle, accountLabel: accountLabel)
    }

    func update(sourceID: UUID, report: CacheHitRateWidgetReport?, periodTitle: String?, accountLabel: String) {
        guard self.sourceID == sourceID else { return }
        self.report = report
        self.periodTitle = periodTitle
        self.accountLabel = accountLabel
    }
}

/// Slot coordinates preserve calendar gaps and repeated DST hours from the report.
struct CacheAnalyticsViewport {
    var zoom = 1.0
    var position = 0.0

    func domain(slotCount: Int) -> ClosedRange<Double> {
        let count = Double(max(slotCount, 1))
        let width = max(1, count / min(max(zoom, 1), count))
        let start = min(max(position, 0), 1) * (count - width) - 0.5
        return start...(start + width)
    }

    func selectedSlot(_ coordinate: Double?, slots: [CacheHitRateWidgetSlot]) -> CacheHitRateWidgetSlot? {
        guard let coordinate, coordinate.isFinite,
              coordinate >= -0.5, coordinate < Double(slots.count) - 0.5 else { return nil }
        let index = Int(coordinate.rounded())
        return slots.first { $0.id == index }
    }
}
