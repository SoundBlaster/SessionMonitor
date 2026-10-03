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

    /// Positive translation moves the plotted data right, revealing earlier slots.
    @discardableResult
    mutating func pan(translation: Double, plotWidth: Double, slotCount: Int) -> Bool {
        guard translation.isFinite, plotWidth.isFinite, plotWidth > 0, slotCount > 0 else { return false }
        let originalPosition = position
        let visible = domain(slotCount: slotCount)
        let width = visible.upperBound - visible.lowerBound
        setStart(visible.lowerBound - translation / plotWidth * width, width: width, slotCount: slotCount)
        return position != originalPosition
    }

    /// Keep the slot beneath the pointer fixed while changing the horizontal span.
    mutating func magnify(by factor: Double, anchor: Double, slotCount: Int) {
        guard factor.isFinite, factor > 0, anchor.isFinite, slotCount > 0 else { return }
        let visible = domain(slotCount: slotCount)
        let oldWidth = visible.upperBound - visible.lowerBound
        let fraction = min(max(anchor, 0), 1)
        let width = min(Double(slotCount), max(1, oldWidth / factor))
        let start = visible.lowerBound + fraction * (oldWidth - width)
        zoom = Double(slotCount) / width
        setStart(start, width: width, slotCount: slotCount)
    }

    mutating func reveal(slot: Double, slotCount: Int) {
        guard slot.isFinite, slotCount > 0 else { return }
        let visible = domain(slotCount: slotCount)
        guard !visible.contains(slot) else { return }
        let width = visible.upperBound - visible.lowerBound
        setStart(slot - width / 2, width: width, slotCount: slotCount)
    }

    private mutating func setStart(_ start: Double, width: Double, slotCount: Int) {
        let travel = Double(slotCount) - width
        position = travel > 0 ? min(max((start + 0.5) / travel, 0), 1) : 0
    }

    /// Invalid gestures preserve the last explicit choice instead of clearing details.
    static func committedSelection(_ coordinate: Double?, previous: Double?, slotCount: Int) -> Double? {
        guard let coordinate, coordinate.isFinite,
              slotCount > 0, coordinate >= -0.5, coordinate < Double(slotCount) - 0.5 else { return previous }
        return max(0, coordinate.rounded())
    }

    func selectedSlot(_ coordinate: Double?, slots: [CacheHitRateWidgetSlot]) -> CacheHitRateWidgetSlot? {
        guard let coordinate, coordinate.isFinite,
              coordinate >= -0.5, coordinate < Double(slots.count) - 0.5 else { return nil }
        let index = Int(coordinate.rounded())
        return slots.first { $0.id == index }
    }
}
